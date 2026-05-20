# frozen_string_literal: true

require "fileutils"

module BrightData
  module LogContext
    THREAD_KEY = :bright_data_log_prefix
    FILE_KEY = :bright_data_log_path
    FILE_MUTEX = Mutex.new
    PREFIX_MUTEX = Mutex.new
    PREFIX_EMITTED = {}

    def self.with_prefix(prefix)
      previous = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = prefix.presence
      yield
    ensure
      Thread.current[THREAD_KEY] = previous
    end

    def self.with_file(path)
      previous = Thread.current[FILE_KEY]
      Thread.current[FILE_KEY] = path.presence&.to_s
      yield
    ensure
      Thread.current[FILE_KEY] = previous
    end

    def self.with_context(prefix: nil, file_path: nil)
      with_prefix(prefix) do
        with_file(file_path) { yield }
      end
    end

    def self.prefix
      Thread.current[THREAD_KEY]
    end

    def self.file_path
      Thread.current[FILE_KEY]
    end

    def self.format(message)
      current = prefix
      text = message.to_s
      current.present? ? "#{current} #{text}" : text
    end

    def self.puts(message = "")
      text = message.to_s
      if prefix.present?
        write_prefix_once(prefix)
        text.split("\n", -1).each { |line| write_line(line) }
      else
        text.split("\n", -1).each { |line| write_line(line) }
      end
    end

    def self.file_puts(path, message = "")
      return if path.blank?

      message.to_s.split("\n", -1).each do |line|
        append_line_to_path(path.to_s, line)
      end
    end

    def self.reset_file(path)
      return if path.blank?

      FileUtils.mkdir_p(File.dirname(path.to_s))
      File.write(path.to_s, "")
    end

    def self.write_line(line, file_line: line)
      Kernel.puts(line)
      append_line(file_line)
    end
    private_class_method :write_line

    def self.write_prefix_once(value)
      PREFIX_MUTEX.synchronize do
        return if PREFIX_EMITTED[value]

        Kernel.puts(value)
        PREFIX_EMITTED[value] = true
      end
    end
    private_class_method :write_prefix_once

    def self.append_line(line)
      path = file_path
      return if path.blank?

      append_line_to_path(path, line)
    end
    private_class_method :append_line

    def self.append_line_to_path(path, line)
      FILE_MUTEX.synchronize do
        FileUtils.mkdir_p(File.dirname(path))
        File.open(path, "a:UTF-8") { |file| file.puts(line) }
      end
    end
    private_class_method :append_line_to_path
  end
end
