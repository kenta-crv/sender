require_relative '../../lib/middleware/twilio_media_stream'

Rails.application.config.middleware.use Middleware::TwilioMediaStream
