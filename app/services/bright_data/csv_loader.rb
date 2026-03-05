# frozen_string_literal: true

require "csv"

module BrightData
  class CsvLoader
    # @param file_path [String] CSVファイルパス
    # @param keyword_column [String] キーワード列名
    #   → クライアントのCSVフォーマットに合わせて変更すること
    #   → 例: "company" なら会社名で検索、"keyword" なら専用キーワード列
    # @return [Array<String>]
    def self.load(file_path, keyword_column: "company")
      raise "File not found: #{file_path}" unless File.exist?(file_path)

      keywords = []
      CSV.foreach(file_path, headers: true, encoding: "BOM|UTF-8") do |row|
        val = row[keyword_column].to_s.strip
        keywords << val if val.present?
      end

      keywords.uniq.tap do |kws|
        puts "[CsvLoader] Loaded #{kws.size} unique keywords from #{file_path}"
      end
    end
  end
end
