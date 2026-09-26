class AutoDialJob < ApplicationJob
  queue_as :auto_dial
  retry_on StandardError, attempts: 0

  # 並列方式: 1ジョブ = 1顧客への発信
  def perform(batch_id, customer_id)
    Rails.logger.info("[AutoDialJob] 開始: batch_id=#{batch_id}, customer_id=#{customer_id}")

    batch = CallBatch.find_by(id: batch_id)
    return unless batch
    return if batch.status.in?(%w[cancelled paused])

    customer = Customer.find_by(id: customer_id)
    unless customer
      batch.record_result!(customer_id, success: false, message: '顧客が見つかりません')
      return
    end

    unless customer.tel.present?
      Call.create!(
        customer: customer,
        call_batch_id: batch.id,
        call_type: 'auto_phone',
        dial_script_id: batch.dial_script_id,
        status: 'リスト不備NG',
        twilio_status: 'failed',
        ended_at: Time.current,
        worker_id: batch.worker_id
      )
      batch.record_result!(customer_id, success: false, message: 'リスト不備NG')
      return
    end

    # 同時回線数チェック
    active_count = Call.active_twilio.where(call_batch_id: batch_id).count
    if active_count >= batch.concurrent_lines
      # 回線が埋まっている場合は5秒後に再エンキュー
      self.class.set(wait: 5.seconds).perform_later(batch_id, customer_id)
      return
    end

    # Callレコード作成
    call = Call.create!(
      customer: customer,
      call_batch_id: batch.id,
      call_type: 'auto_phone',
      dial_script_id: batch.dial_script_id,
      twilio_status: 'queued',
      flow_phase: 'initiating',
      started_at: Time.current,
      worker_id: batch.worker_id
    )

    base_url = TwilioService.public_base_url
    if base_url.blank?
      call.update!(
        twilio_status: 'failed',
        speech_result: '次の文章を返すアドレスが空です。NGROK_URL を設定してください。',
        ended_at: Time.current
      )
      batch.record_result!(customer_id, success: false, message: '次の文章を返すアドレスが空です')
      return
    end

    service = TwilioService.new
    sid = service.initiate_call(customer, call, base_url)
    call.update!(twilio_call_sid: sid, twilio_status: 'initiated')

  rescue => e
    Rails.logger.error("[AutoDialJob] customer_id=#{customer_id} エラー: #{e.message}")
    batch&.record_result!(customer_id, success: false, message: e.message)
  end
end
