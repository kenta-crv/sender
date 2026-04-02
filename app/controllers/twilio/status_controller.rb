module Twilio
  class StatusController < BaseController
    # POST /twilio/status — 通話ステータス変更通知
    def update
      call_sid = params['CallSid']
      status = params['CallStatus']
      duration = params['CallDuration']

      call = Call.find_by(twilio_call_sid: call_sid)
      return head(:ok) unless call

      Rails.logger.info("[TWILIO:STATUS] call_id=#{call.id} Status=#{status} Duration=#{duration}")

      updates = { twilio_status: status }
      updates[:answered_at] = Time.current if status == 'in-progress' && call.answered_at.nil?
      updates[:ended_at] = Time.current if status == 'completed'
      updates[:duration] = duration.to_i if duration.present?

      call.update(updates)

      # バッチの結果記録（通話終了時）
      if status == 'completed' && call.call_batch_id.present?
        batch = call.call_batch
        answered = call.answered_at.present?
        transferred = call.flow_phase == 'transfer'
        batch.record_result!(
          call.customer_id,
          success: answered,
          transferred: transferred,
          message: "#{status} (#{duration}s) phase=#{call.flow_phase}"
        )
      elsif status.in?(%w[busy failed no-answer]) && call.call_batch_id.present?
        call.call_batch.record_result!(
          call.customer_id,
          success: false,
          message: status
        )
      end

      head :ok
    end

    # POST /twilio/recording_status — 録音完了通知
    def recording
      call_sid = params['CallSid']
      recording_sid = params['RecordingSid']
      recording_url = params['RecordingUrl']
      recording_duration = params['RecordingDuration'].to_i

      call = Call.find_by(twilio_call_sid: call_sid)
      return head(:ok) unless call

      config = TwilioConfig.current

      # 最小録音時間を超えた場合のみ保存
      if recording_duration >= config.recording_min_duration
        call.update(
          recording_url: recording_url,
          recording_sid: recording_sid
        )
        Rails.logger.info("[TWILIO:RECORDING] call_id=#{call.id} 保存 (#{recording_duration}s)")
      else
        # 短い録音は削除
        TwilioService.new.delete_recording(recording_sid)
        Rails.logger.info("[TWILIO:RECORDING] call_id=#{call.id} 短いため削除 (#{recording_duration}s)")
      end

      head :ok
    end
  end
end
