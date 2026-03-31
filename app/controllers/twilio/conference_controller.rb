module Twilio
  class ConferenceController < BaseController
    # POST /twilio/conference/status — Conference参加者イベント
    def status
      conference_sid = params['ConferenceSid']
      friendly_name = params['FriendlyName'] || ''
      event = params['StatusCallbackEvent']

      Rails.logger.info("[TWILIO:CONFERENCE] Event=#{event} FriendlyName=#{friendly_name}")

      # Conference名からCallのIDを抽出（transfer_123 → 123）
      call_id = friendly_name.sub('transfer_', '').to_i if friendly_name.start_with?('transfer_')
      return head(:ok) unless call_id

      call = Call.find_by(id: call_id)
      return head(:ok) unless call

      call.update(conference_sid: conference_sid) if call.conference_sid.blank?

      head :ok
    end
  end
end
