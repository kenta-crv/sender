# Twilio の双方向ストリームは 8kHz μ-law だけを再生できる。
module Mulaw
  BIAS = 0x84

  def self.encode(sample)
    sample = sample.to_i
    sign = 0
    if sample.negative?
      sign = 0x80
      sample = -sample
    end
    sample += BIAS
    sample = 0x7FFF if sample > 0x7FFF
    exponent = 7
    mask = 0x4000
    while exponent.positive? && (sample & mask).zero?
      exponent -= 1
      mask >>= 1
    end
    mantissa = (sample >> (exponent + 3)) & 0x0F
    (~(sign | (exponent << 4) | mantissa)) & 0xFF
  end

  def self.decode(byte)
    byte = (~byte) & 0xFF
    sign = byte & 0x80
    exponent = (byte >> 4) & 0x07
    mantissa = byte & 0x0F
    sample = ((mantissa << 3) + BIAS) << exponent
    sample -= BIAS
    sign.zero? ? sample : -sample
  end

  def self.pcm16_to_mulaw(pcm)
    pcm.unpack('s<*').map { |sample| encode(sample) }.pack('C*')
  end

  def self.silence(bytes = 160)
    ("\xFF" * bytes).b
  end

  def self.tone(bytes, amplitude: 8000)
    count = bytes
    samples = Array.new(count) { |i| (Math.sin(i / 8.0) * amplitude).round }
    samples.map { |sample| encode(sample) }.pack('C*')
  end

  def self.rms(mulaw_bytes)
    return 0.0 if mulaw_bytes.nil? || mulaw_bytes.bytesize.zero?

    sum = 0
    mulaw_bytes.each_byte do |byte|
      sample = decode(byte)
      sum += sample * sample
    end
    Math.sqrt(sum.to_f / mulaw_bytes.bytesize)
  end
end
