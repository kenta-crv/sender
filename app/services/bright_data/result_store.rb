# frozen_string_literal: true

require "json"
require "fileutils"

module BrightData
  class ResultStore
    STORE_DIR = Rails.root.join("tmp", "serp_results")

    # バッチ結果を一括保存
    def self.save_batch(batch_results)
      FileUtils.mkdir_p(STORE_DIR)
      filename = "batch_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
      filepath = STORE_DIR.join(filename)

      File.write(filepath, JSON.pretty_generate(batch_results))
      puts "[ResultStore] Saved #{batch_results.size} results to #{filepath}"
      filepath.to_s
    end

    # 最新バッチを読込
    def self.load_latest
      files = Dir[STORE_DIR.join("batch_*.json")].sort
      return [] if files.empty?
      JSON.parse(File.read(files.last))
    end

    # 全バッチ結果を読込
    def self.load_all
      Dir[STORE_DIR.join("batch_*.json")].sort.flat_map do |f|
        JSON.parse(File.read(f))
      end
    end
  end
end
