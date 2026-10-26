require 'digest'
require 'fileutils'
require 'tmpdir'
require_relative '../../lib/mulaw'

# 通話前に原稿の録音を μ-law へ変換して置く。判定後には変換しない。
class DialPlaybackCache
  class NotReady < StandardError; end

  Entry = Struct.new(:branch_id, :recording_id, :transfer, :text, keyword_init: true)

  class << self
    def preload!(script)
      return false unless script && TwilioService.bidirectional_call_script?(script)

      mutex.synchronize do
        rows = entries_for(script)
        raise NotReady, '原稿 ID 1 に再生できる文がありません' if rows.empty?

        loaded = {}
        rows.each do |entry|
          loaded[entry.recording_id] = {
            bytes: bytes_for(script.id, entry),
            branch_id: entry.branch_id,
            transfer: entry.transfer,
            text: entry.text
          }
        end
        memory[script.id] = loaded
      end
      true
    end

    def prime!(script_id, rows)
      loaded = {}
      Array(rows).each do |row|
        recording_id = row[:recording_id].to_s
        loaded[recording_id] = {
          bytes: Mulaw.silence(160),
          branch_id: row[:branch_id].to_s,
          transfer: row[:transfer] == true,
          text: row[:text].to_s
        }
      end
      memory[script_id.to_i] = loaded
    end

    def reset!
      memory.clear
    end

    def fetch(script_id, recording_id)
      memory.dig(script_id.to_i, recording_id.to_s, :bytes)
    end

    def allowlist(script_id)
      Array(memory[script_id.to_i]&.map do |recording_id, row|
        Entry.new(
          branch_id: row[:branch_id],
          recording_id: recording_id,
          transfer: row[:transfer],
          text: row[:text]
        )
      end)
    end

    def entries_for(script)
      rows = []
      DialScript::SCRIPT_KEYS.each do |key|
        next if key == 'faq'

        text = text_for(script, key)
        rows << Entry.new(branch_id: key, recording_id: key, transfer: key == 'transfer', text: text)
      end
      script.dial_faqs.find_each do |faq|
        rows << Entry.new(
          branch_id: 'faq',
          recording_id: "faq-#{faq.id}",
          transfer: false,
          text: faq.answer.to_s
        )
      end
      rows
    end

    private

    def mutex
      @mutex ||= Mutex.new
    end

    def memory
      @memory ||= {}
    end

    def text_for(script, key)
      return DialTransferService::THANKS_TEXT if key == 'transfer'

      picked = script.pick_text_for(key)
      return picked if picked.present?

      TwilioService.script_text(key).to_s
    end

    def bytes_for(script_id, entry)
      return Mulaw.silence(160) if entry.text.blank?

      ready = File.join(Rails.root, 'public', 'audio', "#{entry.recording_id}.ulaw")
      return File.binread(ready) if File.exist?(ready)

      path = cache_path(script_id, entry.recording_id, entry.text)
      return File.binread(path) if File.exist?(path) && File.size(path).positive?

      FileUtils.mkdir_p(File.dirname(path))
      synthesize!(entry.text, path)
      File.binread(path)
    end

    def cache_path(script_id, recording_id, text)
      digest = Digest::SHA256.hexdigest(text.to_s)[0, 16]
      safe_id = recording_id.to_s.gsub(/[^\w\-]/, '_')
      Rails.root.join('tmp/dial_playback', script_id.to_s, "#{safe_id}-#{digest}.ulaw").to_s
    end

    def synthesize!(text, dest)
      Dir.mktmpdir('dial-playback') do |dir|
        aiff = File.join(dir, 'in.aiff')
        wav = File.join(dir, 'in.wav')
        args = ['say', '-o', aiff]
        voice = kyoko_voice
        args += ['-v', voice] if voice
        args << text
        unless system(*args, out: File::NULL, err: File::NULL) && File.exist?(aiff)
          raise NotReady, '通話前の読み上げ生成に失敗しました'
        end
        unless system('afconvert', '-f', 'WAVE', '-d', 'LEI16@8000', '-c', '1', aiff, wav, out: File::NULL, err: File::NULL) && File.exist?(wav)
          raise NotReady, 'Twilio再生形式への変換に失敗しました'
        end
        File.binwrite(dest, Mulaw.pcm16_to_mulaw(pcm16_from_wav(wav)))
      end
    end

    def kyoko_voice
      return @kyoko_voice if defined?(@kyoko_voice)

      list = `say -v '?' 2>/dev/null`
      @kyoko_voice = list.include?('Kyoko') ? 'Kyoko' : nil
    end

    def pcm16_from_wav(path)
      data = File.binread(path)
      index = data.index('data')
      raise NotReady, '変換後の音声に data がありません' unless index

      size = data[index + 4, 4].unpack1('V')
      data[index + 8, size]
    end
  end
end
