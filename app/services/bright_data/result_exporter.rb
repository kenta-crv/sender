# frozen_string_literal: true

require "csv"

module BrightData
  class ResultExporter
    def self.print_table(companies)
      puts "\n#{'='*100}"
      puts "抽出結果: #{companies.size}件"
      puts "#{'='*100}"

      companies.each_with_index do |c, i|
        puts "\n--- #{i + 1} ---"
        puts "  会社名:       #{c[:company] || '(未取得)'}"
        puts "  電話番号:     #{c[:tel] || '(未取得)'}"
        puts "  住所:         #{c[:address] || '(未取得)'}"
        puts "  URL:          #{c[:url] || '(未取得)'}"
        puts "  問合せページ: #{c[:contact_url] || '(未取得)'}"
        puts "  業種:         #{c[:industry] || '(未取得)'}"
        puts "  ソース:       #{c[:source]}"
      end
    end

    def self.to_csv(companies, output_path: nil)
      output_path ||= Rails.root.join("tmp", "extracted_companies_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv")

      CSV.open(output_path, "w", encoding: "UTF-8") do |csv|
        csv << %w[会社名 電話番号 住所 URL 問合せページ 業種 ソース 検索クエリ]
        companies.each do |c|
          csv << [c[:company], c[:tel], c[:address], c[:url], c[:contact_url], c[:industry], c[:source], c[:query]]
        end
      end

      puts "[ResultExporter] CSV saved: #{output_path} (#{companies.size}件)"
      output_path.to_s
    end
  end
end
