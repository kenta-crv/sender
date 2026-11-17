require 'net/imap'

# mail@j-work.jp の受信箱を読み、新しいメールを判定して保存する。
# EXAMINE（読み取り専用）と BODY.PEEK を使うので、受信箱の既読状態は変わらない。
#
# 使い方:
#   ReplyFetchJob.perform_now                 # 新しいメールの取り込み（毎日1時に自動実行）
#   ReplyFetchJob.perform_now('reclassify')       # 取り込み済みのメールを今のルールで判定し直す（手動で直した分は変えない）
#   ReplyFetchJob.perform_now('reclassify', 50)   # 新しい順に50件だけ判定し直す（テスト用）
#   ReplyFetchJob.perform_now('backfill')         # 直近14日分のうち、まだ保存できていないメールだけ取り込む
class ReplyFetchJob < ApplicationJob
  queue_as :default

  FIRST_RUN_DAYS = 14    # 初回は直近14日分だけ取り込む
  BATCH_LIMIT = 1000     # 1回で取り込む上限（1日1回のため多めにしている）
  MATCH_WINDOW = 14.days # 送信記録と照合する期間

  def perform(mode = 'fetch', limit = nil)
    started_at = Time.current
    imap = connect
    return unless imap

    uidvalidity = imap.responses['UIDVALIDITY']&.last.to_i

    if mode == 'reclassify'
      reclassify(imap, uidvalidity, limit)
      return
    end

    if mode == 'backfill'
      stored = InboundReply.where(imap_uidvalidity: uidvalidity).pluck(:imap_uid)
      missing = imap.uid_search(['SINCE', FIRST_RUN_DAYS.days.ago.strftime('%d-%b-%Y')]) - stored
      each_mail(imap, missing.sort) { |uid, raw| store(uid, uidvalidity, raw) }
      Rails.logger.info("[ReplyFetchJob] 取りこぼし#{missing.size}件を取り込み")
      return
    end

    last_uid = InboundReply.where(imap_uidvalidity: uidvalidity).maximum(:imap_uid)
    uids =
      if last_uid
        imap.uid_search(['UID', "#{last_uid + 1}:*"]).select { |u| u > last_uid }
      else
        imap.uid_search(['SINCE', FIRST_RUN_DAYS.days.ago.strftime('%d-%b-%Y')])
      end
    uids = uids.sort.first(BATCH_LIMIT)

    each_mail(imap, uids) { |uid, raw| store(uid, uidvalidity, raw) }
    Rails.logger.info("[ReplyFetchJob] #{uids.size}件を取り込み")
    @imported_since = started_at
  ensure
    begin
      imap&.logout
      imap&.disconnect
    rescue StandardError
      nil
    end
    send_digest if @imported_since
  end

  private

  def connect
    host = ENV['REPLY_IMAP_HOST']
    user = ENV['REPLY_IMAP_USER']
    pass = ENV['REPLY_IMAP_PASSWORD']
    if [host, user, pass].any?(&:blank?)
      Rails.logger.warn('[ReplyFetchJob] REPLY_IMAP_* が未設定のため停止')
      return nil
    end

    imap = Net::IMAP.new(host, port: (ENV['REPLY_IMAP_PORT'].presence || 993).to_i, ssl: true)
    imap.login(user, pass)
    imap.examine('INBOX')
    imap
  end

  def each_mail(imap, uids)
    uids.each_slice(20) do |slice|
      (imap.uid_fetch(slice, ['UID', 'BODY.PEEK[]']) || []).each do |data|
        yield data.attr['UID'], data.attr['BODY[]']
      end
    end
  end

  def store(uid, uidvalidity, raw)
    return if InboundReply.exists?(imap_uidvalidity: uidvalidity, imap_uid: uid)

    mail = Mail.read_from_string(raw.to_s)
    return if mail.header['X-Okurite-Reply-Digest'].present?

    InboundReply.create!(
      { imap_uid: uid, imap_uidvalidity: uidvalidity }.merge(attributes_for(mail))
    )
  rescue StandardError => e
    Rails.logger.error("[ReplyFetchJob] uid=#{uid} 取り込み失敗: #{e.class} #{e.message}")
  end

  def reclassify(imap, uidvalidity, limit = nil)
    scope = InboundReply.where(imap_uidvalidity: uidvalidity).order(imap_uid: :desc)
    scope = scope.limit(limit.to_i) if limit.to_i > 0
    records = scope.index_by(&:imap_uid)
    count = 0
    each_mail(imap, records.keys.sort) do |uid, raw|
      reply = records[uid]
      next unless reply
      reply.update!(attributes_for(Mail.read_from_string(raw.to_s)))
      count += 1
    rescue StandardError => e
      Rails.logger.error("[ReplyFetchJob] uid=#{uid} 判定し直し失敗: #{e.class} #{e.message}")
    end
    Rails.logger.info("[ReplyFetchJob] #{count}件を判定し直し")
  end

  def attributes_for(mail)
    from = Array(mail.from).first.to_s.downcase
    from_domain = SentMessage.domain_from(from)
    received_at = mail.date&.to_time || Time.current
    sent = find_sent(from_domain, received_at)
    result = ReplyClassifier.new(mail, sent_message: sent).call

    {
      message_id: mail.message_id,
      from_address: from,
      from_domain: from_domain,
      subject: mail.subject.to_s.scrub(''),
      body: ReplyClassifier.body_text(mail).truncate(20_000),
      received_at: received_at,
      classification: result.classification,
      intent: result.intent,
      ai_used: result.ai_used,
      score: result.score,
      reasons: result.reasons.join(' / '),
      sent_message_id: sent&.id,
      customer_id: sent&.customer_id
    }
  end

  # 差出人ドメインが送信先と一致し、受信より前で最も近い送信記録
  def find_sent(domain, received_at)
    return nil if domain.blank?
    SentMessage.where(domain: domain)
               .where(sent_at: (received_at - MATCH_WINDOW)..(received_at + 5.minutes))
               .order(sent_at: :desc).first
  end

  # 今回取り込んだ分の件数を、一覧のURL付きでメール通知する（0件の日も送る）
  def send_digest
    scope = InboundReply.where('created_at >= ?', @imported_since)
    counts = InboundReply::CLASSIFICATIONS.keys.index_with { |c| scope.where(classification: c).count }
    intents = InboundReply::INTENTS.keys.index_with { |i| scope.where(classification: 'human', intent: i).count }
    ReplyDigestMailer.daily(counts, intents).deliver_now
  rescue StandardError => e
    Rails.logger.error("[ReplyFetchJob] 通知メールの送信に失敗: #{e.class} #{e.message}")
  end
end
