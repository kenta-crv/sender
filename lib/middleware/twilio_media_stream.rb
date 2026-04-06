require 'faye/websocket'
require_relative '../media_stream_handler'

module Middleware
  class TwilioMediaStream
    MEDIA_STREAM_PATH = '/media-stream'

    def initialize(app)
      @app = app
    end

    def call(env)
      if Faye::WebSocket.websocket?(env) && env['PATH_INFO'] == MEDIA_STREAM_PATH
        handle_websocket(env)
      else
        @app.call(env)
      end
    end

    private

    def handle_websocket(env)
      ws = Faye::WebSocket.new(env)
      handler = MediaStreamHandler.new(ws)

      ws.on(:open) do |event|
        Rails.logger.info("[MediaStream] WebSocket接続開始")
      end

      ws.on(:message) do |event|
        handler.on_message(event)
      end

      ws.on(:close) do |event|
        handler.on_close(event)
        Rails.logger.info("[MediaStream] WebSocket接続終了")
      end

      ws.rack_response
    end
  end
end
