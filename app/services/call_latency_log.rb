require 'json'
require 'fileutils'

# 通話IDごとの時刻を残し、発話終了から録音送信までの時間を出す。
class CallLatencyLog
  class << self
    attr_writer :store_dir

    def store_dir
      @store_dir || Rails.root.join('tmp/call_latency')
    end

    def record(call_id, event, turn_id: nil, at_mono: nil, extra: {})
      return if call_id.blank?

      entry = {
        'event' => event.to_s,
        'turn_id' => turn_id,
        'mono' => at_mono || Process.clock_gettime(Process::CLOCK_MONOTONIC),
        'wall' => Time.now.utc.iso8601(3),
        'extra' => extra || {}
      }
      # 通話の音声を扱う処理を止めないよう、書き込みは別スレッドで行う（時刻はこの時点のもの）
      enqueue(file_path(call_id), entry)
      entry
    rescue => e
      Rails.logger.error("[CallLatency] record error: #{e.message}")
      nil
    end

    # 書き込み待ちがなくなるまで待つ（読む前に呼ぶ）
    def flush(timeout = 3)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      sleep 0.01 while pending.positive? && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
    end

    def events(call_id)
      flush
      path = file_path(call_id)
      return [] unless File.exist?(path)

      read_rows(path)
    end

    def clear!(call_id)
      flush
      path = file_path(call_id)
      FileUtils.rm_f(path)
    end

    def response_samples(call_id, kind: 'utterance', mark: false)
      grouped(call_id).filter_map do |_turn_id, rows|
        start = rows.find { |row| row['event'] == 'utterance_end' }
        next unless start
        next if kind && start.dig('extra', 'kind').to_s != kind

        finish_name = mark ? 'playback_mark' : 'audio_first_sent'
        finish = rows.find { |row| row['event'] == finish_name }
        next unless finish

        (finish['mono'] - start['mono']) * 1000.0
      end
    end

    def percentiles(samples)
      values = Array(samples).map(&:to_f).sort
      return { n: 0, p50: nil, p95: nil } if values.empty?

      { n: values.size, p50: percentile(values, 50), p95: percentile(values, 95) }
    end

    def turn_rows(call_id)
      grouped(call_id).map do |turn_id, rows|
        { turn_id: turn_id, breakdown_ms: breakdown(rows), events: rows }
      end
    end

    def report(call_id)
      lines = []
      turn_rows(call_id).each do |turn|
        parts = turn[:breakdown_ms].map { |key, ms| "#{key}=#{ms}ms" }.join(' ')
        lines << "turn #{turn[:turn_id]}: #{parts}"
      end
      sent = percentiles(response_samples(call_id))
      marked = percentiles(response_samples(call_id, mark: true))
      lines << "送信までの p50=#{fmt(sent[:p50])} p95=#{fmt(sent[:p95])} n=#{sent[:n]}"
      lines << "再生印までの p50=#{fmt(marked[:p50])} p95=#{fmt(marked[:p95])} n=#{marked[:n]}"
      lines.join("\n")
    end

    private

    def mutex
      @mutex ||= Mutex.new
    end

    def pending
      mutex.synchronize { @pending.to_i }
    end

    def enqueue(path, entry)
      mutex.synchronize do
        @pending = @pending.to_i + 1
        @queue ||= Queue.new
        @writer = nil unless @writer&.alive?
        @writer ||= Thread.new { write_loop }
      end
      @queue << [path, entry]
    end

    def write_loop
      loop do
        path, entry = @queue.pop
        begin
          FileUtils.mkdir_p(File.dirname(path))
          rows = read_rows(path)
          rows << entry
          File.write(path, JSON.generate(rows))
        rescue => e
          Rails.logger.error("[CallLatency] write error: #{e.message}")
        ensure
          mutex.synchronize { @pending -= 1 }
        end
      end
    end

    def file_path(call_id)
      File.join(store_dir.to_s, "#{call_id}.json")
    end

    def read_rows(path)
      return [] unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      []
    end

    def grouped(call_id)
      events(call_id).group_by { |row| row['turn_id'] }
    end

    def breakdown(rows)
      indexed = rows.map { |row| [row['event'], row['mono']] }.to_h
      origin = indexed['utterance_end']
      result = {}
      indexed.each do |name, mono|
        next if name == 'utterance_end' || origin.nil?

        result[name] = ((mono - origin) * 1000.0).round(1)
      end
      if indexed['transcript_final'] && indexed['branch_confirmed']
        result['ai_ms'] = ((indexed['branch_confirmed'] - indexed['transcript_final']) * 1000.0).round(1)
      end
      if indexed['branch_confirmed'] && indexed['audio_first_sent']
        result['send_ms'] = ((indexed['audio_first_sent'] - indexed['branch_confirmed']) * 1000.0).round(1)
      end
      result
    end

    def percentile(sorted, percent)
      return sorted.first.round(1) if sorted.size == 1

      rank = (percent / 100.0) * (sorted.size - 1)
      low = sorted[rank.floor]
      high = sorted[rank.ceil]
      (low + (high - low) * (rank - rank.floor)).round(1)
    end

    def fmt(value)
      value.nil? ? 'なし' : "#{value}ms"
    end
  end
end
