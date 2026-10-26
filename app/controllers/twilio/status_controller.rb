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
      call.reload
      if status.in?(%w[completed busy failed no-answer canceled cancelled])
        call.apply_manual_status!(status)
        DialTransferService.cancel_operator!(call)
      end

      # バッチの結果記録（通話終了時）
      if status == 'completed' && call.call_batch_id.present?
        batch = call.call_batch
        answered = call.answered_at.present?
        transferred = call.flow_phase.to_s.start_with?('transfer')
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

    # POST /twilio/amd — 留守番電話は着信不在
    def amd
      call_sid = params['CallSid']
      answered_by = params['AnsweredBy'].to_s
      call = Call.find_by(twilio_call_sid: call_sid)
      return head(:ok) unless call

      Rails.logger.info("[TWILIO:AMD] call_id=#{call.id} AnsweredBy=#{answered_by}")
      human_spoke = call.speech_result.to_s.include?('相手:')
      if answered_by == 'machine_end_other' && human_spoke
        head :ok
        return
      end
      if answered_by.start_with?('machine') || answered_by == 'fax'
        call.save_selected_status!('着信不在')
        call.update(flow_phase: 'ended')
        DialTransferService.cancel_operator!(call)
        TwilioService.new.hangup_call(call_sid)
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

      connected = call.answered_at.present? || recording_duration.positive?
      if connected
        call.update(
          recording_url: recording_url,
          recording_sid: recording_sid
        )
        Rails.logger.info("[TWILIO:RECORDING] call_id=#{call.id} 保存 (#{recording_duration}s)")
      else
        TwilioService.new.delete_recording(recording_sid)
        Rails.logger.info("[TWILIO:RECORDING] call_id=#{call.id} 未接続のため削除")
      end

      head :ok
    end
  end
end
