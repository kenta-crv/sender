class Call < ApplicationRecord

  #belongs_to :customer, foreign_key: :tel, primary_key: :tel
  #belongs_to :worker
  belongs_to :customer
  belongs_to :worker, optional: true
  belongs_to :call_batch, optional: true
  belongs_to :dial_script, optional: true
  belongs_to :pending_faq, class_name: 'DialFaq', optional: true
  has_many :dial_unknown_utterances, dependent: :nullify
  # Validations for recording fields
  #validates :recording_url, presence: true, if: :recording_duration?
  #validates :recording_duration, numericality: { greater_than: 0 }, if: :recording_duration?
  
  # call_type スコープ
  scope :phone_calls, -> { where(call_type: [nil, 'phone']) }
  scope :form_submissions, -> { where(call_type: 'form') }
  scope :auto_calls, -> { where(call_type: 'auto_phone') }

  # Twilio通話ステータス
  scope :active_twilio, -> { where(twilio_status: ['initiated', 'ringing', 'in-progress']) }
  scope :with_recording, -> { where.not(recording_url: nil) }

  # Scope for automated calls
  scope :automated, -> { where.not(vapi_call_id: nil) }
  scope :times_last_call, -> {
    last_time = "SELECT sub_call.customer_id, MAX(sub_call.time) as last_time FROM calls as sub_call GROUP BY sub_call.customer_id";
    joins(
      "INNER JOIN (#{last_time}) AS sub ON sub.customer_id = calls.customer_id AND sub.last_time = calls.time"
    ).group(:customer_id)
  }

  scope :joins_last_call, -> {
    last_created_at = "SELECT sub_call.customer_id, MAX(sub_call.created_at) as last_created_at FROM calls as sub_call GROUP BY sub_call.customer_id";
    joins(
      "INNER JOIN (#{last_created_at}) AS sub ON sub.customer_id = calls.customer_id AND sub.last_created_at = calls.created_at"
    ).group(:customer_id)
  }

  scope :last_call_notification, ->(sender_id){
    includes(customer: :contact_trackings).where(contact_trackings: { id: ContactTracking.latest(sender_id).select(:id) })
  }

  scope :call_count_today, -> {
    where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
  }

  scope :call_count_hour, -> {
    where(statu: ["着信留守", "担当者不在","フロントNG","見込","APP","NG","クロージングNG","受付NG","自己紹介NG","質問段階NG","日程調整NG","リスト不備NG"]).where(created_at: Time.current.beginning_of_hour..Time.current.end_of_hour)
  }

  scope :basic_count_today, -> {
    call_count_today.where(statu: ["着信留守", "担当者不在","フロントNG","見込","APP","NG","クロージングNG","受付NG","自己紹介NG","質問段階NG","日程調整NG"])
  }

  # 本日獲得見込数
  scope :protect_count_today, -> {
    call_count_today.where(statu: "見込")
  }

  # 本日アポ数
  scope :app_count_today, -> {
    call_count_today.where(statu: "APP")
  }

  scope :unread_notification, -> {
    where.not(time: nil)
      .where('latest_confirmed_time is null or time >= latest_confirmed_time')
  }

  scope :between_created_at, ->(from, to){
    where(created_at: from..to)
  }

    def self.call_attributes
      ["customer" ,"statu", "time", "comment", "created_at","updated_at"]
    end

  # 自動発信のAIが付ける結果はこれだけ。
  AI_STATUS_ITEMS = %w[着信不在 フロントアウト 担当者不在 電話不通].freeze

  @@StatuItems = [
    "着信不在",
    "フロントアウト",
    "担当者不在",
    "電話不通",
    "着信留守",
    #"フロントNG",
    "見込",
    "APP",
    "APPキャンセル",
    #"NG",
    "受付NG",
    "自己紹介NG",
    "質問段階NG",
    "日程調整NG",
    "クロージングNG",
    "永久NG",
    #"契約",
    "再掲載",
    #"未提案",
    #"再コール",
    #"見積中",
    #"見込高",
    #"見込中",
    #"見込低",
    #"再APP",
    "リスト不備NG"
  ]
  def self.StatuItems
    @@StatuItems
  end

  def self.AiStatusItems
    AI_STATUS_ITEMS
  end

  def save_selected_status!(label)
    stored = label.to_s == 'callback' ? '担当者不在' : label.to_s
    return unless self.class.StatuItems.include?(stored) || AI_STATUS_ITEMS.include?(stored)

    update!(status: stored)
  end

  def apply_manual_status!(twilio_status)
    return if AI_STATUS_ITEMS.include?(status.to_s)
    return if self.class.StatuItems.include?(status)

    label = case twilio_status.to_s
            when 'no-answer'
              '着信不在'
            when 'busy', 'failed', 'canceled', 'cancelled'
              '電話不通'
            end
    save_selected_status!(label) if label
  end

  @@sfa_status = [
    ["未提案","未提案"],
    ["再コール","再コール"],
    ["再APP","再APP"],
    ["見積中","見積中"],
    ["見込高","見込高"],
    ["見込中","見込中"],
    ["見込低","見込低"],
    ["契約","契約"],
    ["予算感NG","予算感NG"],
    ["時期NG","時期NG"],
    ["NG","NG"],
    ["永久NG","永久NG"],
    ["契約終了","契約終了"],
    ["Comicomi案件","Comicomi案件"]
  ]
  def self.SfaStatus
    @@sfa_status
  end

  # 見込数
  def self.protect_convertion
    (Call.protect_count_today.count.to_f / Call.basic_count_today.count.to_f) * 100
  end

  # アポ率
  def self.app_convertion
    (Call.app_count_today.count.to_f / Call.basic_count_today.count.to_f) * 100
  end

  # 活動中ユーザ数
  def self.active_user_count
    Call.basic_count_today.group(:user_id).having('count(*) > 0').count.count
  end

  def date_count
    Call.group("DATE_FORMAT(created_at, '%Y-%m-%d')").count
  end

  def week_count
    Call.group("WEEK(created_at)").count
  end

  def month_count
    Call.group("MONTH(created_at)").count
  end

  def append_call_turn!(speaker, text, script: nil)
    line = if speaker.to_s == 'them'
             "相手: #{text}"
           else
             "こちら[#{script}]: #{text}"
           end
    body = [speech_result, line].compact.reject(&:blank?).join("\n")
    updates = {
      speech_result: body.last(4000),
      speech_detected_at: Time.current
    }
    updates[:speech_category] = script.to_s if script.present?
    updates[:flow_phase] = 'ended' if TwilioService.hangup_script?(script)
    update(updates)
    CallTranscriptBroadcaster.broadcast(
      id,
      speaker: speaker,
      text: text,
      interim: false,
      script: script
    )
  end

  def conversation_context_hash
    JSON.parse(conversation_context.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  # 直前のやりとりと話題を通話に残す
  def remember_context!(them:, script:, us:)
    ctx = conversation_context_hash
    turns = Array(ctx['turns'])
    turns << {
      'them' => them.to_s,
      'script' => script.to_s,
      'us' => us.to_s,
      'at' => Time.current.iso8601
    }
    turns = turns.last(8)
    topic = case script.to_s
            when 'faq' then 'faq'
            when 'purpose', 'smalltalk' then 'purpose'
            when 'wait' then 'wait'
            when 'clarify', 'clarify_alt', 'clarify_simple' then ctx['topic'].presence || 'clarify'
            when 'callback' then 'closing'
            when *self.class.StatuItems then 'status'
            else ctx['topic'].presence || script.to_s
            end
    ctx = ctx.merge(
      'turns' => turns,
      'last_them' => them.to_s,
      'last_script' => script.to_s,
      'last_us' => us.to_s,
      'topic' => topic
    )
    if persisted?
      update(conversation_context: JSON.generate(ctx))
    else
      assign_attributes(conversation_context: JSON.generate(ctx))
    end
  end

  def context_summary_for_classifier
    ctx = conversation_context_hash
    parts = []
    parts << "話題: #{ctx['topic']}" if ctx['topic'].present?
    Array(ctx['turns']).last(3).each do |turn|
      parts << "相手: #{turn['them']}"
      parts << "こちら[#{turn['script']}]: #{turn['us']}"
    end
    parts.join("\n")
  end

  def user_time_count #時間単位のカウント
    Call.where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
  end

  #def user_app
  #  U
  #end

end