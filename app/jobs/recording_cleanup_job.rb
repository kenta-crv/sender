class RecordingCleanupJob < ApplicationJob
  queue_as :default

  # 30日超の録音を削除
  def perform
    config = TwilioConfig.current
    retention_days = 30
    service = TwilioService.new

    calls = Call.with_recording.where('created_at < ?', retention_days.days.ago)

    calls.find_each do |call|
      service.delete_recording(call.recording_sid)
      call.update_columns(recording_url: nil, recording_sid: nil)
      Rails.logger.info("[RecordingCleanup] 削除: call_id=#{call.id} recording_sid=#{call.recording_sid}")
    end
  end
end
