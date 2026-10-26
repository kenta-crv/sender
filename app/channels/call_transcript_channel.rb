class CallTranscriptChannel < ApplicationCable::Channel
  def subscribed
    call = Call.find_by(id: params[:call_id])
    reject unless call && current_admin

    stream_from "call_transcript_#{call.id}"
  end
end
