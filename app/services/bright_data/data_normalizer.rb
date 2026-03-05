# frozen_string_literal: true

module BrightData
  class DataNormalizer
    # ★ クライアントの正規表現ルールが届いたら各メソッドを修正 ★

    def self.normalize(company_hash)
      {
        company:     normalize_company_name(company_hash[:company]),
        tel:         normalize_phone(company_hash[:tel]),
        address:     normalize_address(company_hash[:address]),
        url:         normalize_url(company_hash[:url]),
        contact_url: normalize_url(company_hash[:contact_url]),
        industry:    company_hash[:industry]&.strip
      }
    end

    def self.normalize_batch(companies)
      companies.map { |c| normalize(c) }
    end

    private

    def self.normalize_company_name(name)
      return nil if name.blank?
      name.strip.gsub("　", " ").gsub(/\s+/, " ")
          .gsub(/[（\(]株[）\)]/, "株式会社")
          .gsub(/[（\(]有[）\)]/, "有限会社")
          .gsub(/[（\(]合[）\)]/, "合同会社")
    end

    def self.normalize_phone(tel)
      return nil if tel.blank?
      tel.tr("０-９", "0-9")
         .gsub(/[ー－—–‐‑−]/, "-")
         .gsub(/[^\d\-+]/, "")
         .presence
    end

    def self.normalize_address(address)
      return nil if address.blank?
      address.strip.tr("０-９", "0-9").gsub(/[ー－—–]/, "-")
    end

    def self.normalize_url(url)
      return nil if url.blank?
      url = url.strip
      url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)
      url
    end
  end
end
