# 通話中の文字を保存前でも画面へ送る。
class CallTranscriptBroadcaster
  def self.broadcast(call_id, speaker:, text:, interim: false, script: nil, status: nil)
    return if call_id.blank?
    return if text.to_s.strip.blank?

    status = 'interim' if status.nil? && interim
    ActionCable.server.broadcast(
      "call_transcript_#{call_id}",
      {
        call_id: call_id.to_i,
        speaker: speaker.to_s,
        text: text.to_s,
        interim: interim == true || status == 'interim',
        status: status,
        script: script.to_s.presence,
        at: Time.current.iso8601
      }
    )
  rescue => e
    Rails.logger.error("[CallTranscriptBroadcaster] call_id=#{call_id} error: #{e.message}")
  end
end
