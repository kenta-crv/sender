# 受信メールを「自動受付 / 人の返信 / メルマガ・迷惑 / 不明」に分ける。
# はっきりしたものはルールで決め、残りだけを AI（ReplyAiClassifier）に回す。
# AI が使えない・失敗したときは、ルールの点数で決める。
class ReplyClassifier
  AUTO_THRESHOLD = 80     # 点数がこれ以上なら AI に回さず自動受付
  UNKNOWN_THRESHOLD = 40  # AI が使えないとき、これ以上は不明・未満は人の返信

  AUTO_SUBJECT = /自動返信|自動応答|自動送信|自動配信|確認メール|受付完了|受け?付け?(いた)?し?ました|受付いたし|送信完了|送信(いただき|頂き)?(誠に)?ありがと|お問い?合わ?せ(を|に)?(いただき|頂き|下さり|くださり)?(まして)?(誠に|まことに)?ありがと|お問い?合わ?せ(内容|の)?(確認|受付)|auto.?reply|automatic reply|out of office/i
  NOREPLY_FROM = /no-?reply|do-?not-?reply|auto(reply|responder)?@|system@|wordpress@|wix-forms/i
  BOUNCE_FROM = /mailer-daemon|postmaster/i
  BOUNCE_SUBJECT = /returned mail|undeliver|delivery status|failure notice|配信(不能|エラー|失敗)|届きませんでした/i
  # 迷惑メールが件名に混ぜる見えない文字
  INVISIBLE_CHARS = /[​-‍⁠﻿]/

  Result = Struct.new(:classification, :intent, :score, :reasons, :ai_used)

  def initialize(mail, sent_message: nil)
    @mail = mail
    @sent = sent_message
  end

  def call
    subject = @mail.subject.to_s
    from = Array(@mail.from).join(',')

    # 1. ルールで確定するもの
    if from =~ BOUNCE_FROM || subject =~ BOUNCE_SUBJECT
      return Result.new('other', nil, 0, ['届かなかった通知（バウンス）'], false)
    end
    return Result.new('auto', nil, 100, ['Auto-Submittedヘッダ'], false) if auto_submitted?
    return Result.new('auto', nil, 100, ['自動応答ヘッダ'], false) if header('X-Autoreply').present? || header('X-Autorespond').present? || header('Precedence') =~ /auto_reply/i
    return Result.new('other', nil, 0, ['配信停止ヘッダ（メルマガ）'], false) if header('List-Unsubscribe').present? || header('List-Id').present?
    return Result.new('other', nil, 0, ['一斉配信ヘッダ'], false) if header('Precedence') =~ /bulk|list|junk/i
    return Result.new('other', nil, 0, ['件名に見えない文字（迷惑メール）'], false) if subject =~ INVISIBLE_CHARS || from =~ INVISIBLE_CHARS

    score, reasons = rule_score(subject, from)
    return Result.new('auto', nil, score, reasons, false) if score >= AUTO_THRESHOLD

    # 2. 残りを AI で
    ai = ReplyAiClassifier.call(from: from, subject: subject, body: self.class.body_text(@mail), matched_send: @sent.present?)
    if ai
      return Result.new(ai[:category], ai[:intent], score, reasons + ["AI: #{ai[:reason]}"], true)
    end

    # 3. AI が使えないときは点数で
    classification = score >= UNKNOWN_THRESHOLD ? 'unknown' : 'human'
    Result.new(classification, nil, score, reasons + ['AI未使用'], false)
  end

  # メール本文（テキスト優先、なければHTMLからタグを除く）
  def self.body_text(mail)
    part = mail.multipart? ? (mail.text_part || mail.html_part) : mail
    return '' unless part
    text = part.decoded.to_s
    text = text.dup.force_encoding('UTF-8').scrub('')
    if part.mime_type == 'text/html'
      text = ActionView::Base.full_sanitizer.sanitize(text.gsub(/<br\s*\/?>|<\/p>/i, "\n"))
    end
    text
  rescue StandardError
    ''
  end

  private

  def rule_score(subject, from)
    score = 0
    reasons = []
    add = ->(points, reason) { score += points; reasons << "#{reason}(#{points > 0 ? '+' : ''}#{points})" }

    add.(50, 'X-Auto-Response-Suppressヘッダ') if header('X-Auto-Response-Suppress').present?
    add.(60, '差出人がnoreply等') if from =~ NOREPLY_FROM
    add.(30, '件名が受付の定型') if subject =~ AUTO_SUBJECT

    if @sent && @mail.date
      minutes = (@mail.date.to_time - @sent.sent_at) / 60.0
      if minutes.between?(-2, 15)
        add.(40, '送信から15分以内')
      elsif minutes.between?(15, 60)
        add.(20, '送信から1時間以内')
      end
    end

    ratio = copy_ratio
    add.(40, "送った文面の写し#{(ratio * 100).round}%") if ratio && ratio >= 0.3

    # 自動受付はこちらのメールへの返信にはならないため、返信の印があれば人の可能性が高い
    add.(-40, '返信の印(In-Reply-To)') if header('In-Reply-To').present? || header('References').present?

    [score, reasons]
  end

  def auto_submitted?
    v = header('Auto-Submitted')
    v.present? && v.downcase != 'no'
  end

  def header(name)
    @mail.header[name]&.value.to_s
  rescue StandardError
    ''
  end

  # 送った文面の行のうち、受信本文に含まれる割合（引用記号 > の行は除く）
  def copy_ratio
    return nil unless @sent&.body.present?
    received = self.class.body_text(@mail).lines
                   .reject { |l| l.lstrip.start_with?('>') }
                   .map { |l| normalize(l) }.join
    sent_lines = @sent.body.lines.map { |l| normalize(l) }.select { |l| l.size >= 8 }
    return nil if sent_lines.empty?
    hit = sent_lines.count { |l| received.include?(l) }
    hit.to_f / sent_lines.size
  end

  def normalize(str)
    str.to_s.unicode_normalize(:nfkc).gsub(/[[:space:]]/, '')
  end
end
