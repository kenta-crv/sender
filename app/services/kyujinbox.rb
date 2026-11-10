module Kyujinbox
  INDUSTRY = "SAP".freeze
  PAGE_INTERVAL = 1
  COMPANY_KEY_LENGTH = 8
  LEGAL_ENTITY_TERMS = %w[合資会社 株式会社 合同会社 社会福祉法人 有限会社].freeze
  EXCLUDE_WORD = "派遣".freeze
  USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36".freeze

  Posting = Struct.new(
    :company_raw, :company_clean, :title, :area, :employ_type, :posting_url, :job_key,
    :updated_text, :source_text,
    keyword_init: true
  )
  Page = Struct.new(:postings, :next_url, keyword_init: true)

  def self.start_urls
    Pipeline::Campaign.sap.start_urls
  end

  def self.backfill_urls
    Pipeline::Campaign.sap.backfill_urls
  end

  def self.title_relevant?(title, keywords = :default)
    list = keywords == :default ? title_keywords : Array(keywords)
    return true if list.empty?

    normalized = title.to_s.unicode_normalize(:nfkc).upcase
    list.any? { |keyword| normalized.include?(keyword.to_s.unicode_normalize(:nfkc).upcase) }
  end

  def self.title_keywords
    Pipeline::Campaign.sap.title_keywords
  end

  def self.excluded?(posting, words = :default)
    list = words == :default ? [EXCLUDE_WORD] : Array(words).map(&:to_s).reject(&:blank?)
    return false if list.empty?

    fields = [
      posting.company_raw, posting.area, posting.title, posting.employ_type,
      posting.updated_text, posting.source_text
    ]
    fields.any? { |field| list.any? { |word| field.to_s.include?(word) } }
  end

  def self.legal_entity?(name)
    value = base_company_name(name)
    LEGAL_ENTITY_TERMS.any? { |term| value.start_with?(term) || value.end_with?(term) }
  end

  def self.clean_company(name)
    value = base_company_name(name)
    LEGAL_ENTITY_TERMS.each do |term|
      return value.delete_prefix(term).strip if value.start_with?(term)
    end
    value
  end

  # 「株式会社／東海」「株式会社（東京）」のように、社名の後ろの地区を外す。
  def self.base_company_name(name)
    name.to_s.strip.split(%r{[／/(（]}, 2).first.to_s.strip
  end

  def self.company_key(company_clean, posting_url)
    company_clean.to_s[0, COMPANY_KEY_LENGTH].presence || posting_url.to_s
  end

  def self.job_key_for(url, company_raw, title)
    fallback = "#{company_raw}#{title}"
    return fallback if url.blank?

    uri = URI.parse(url)
    path = uri.path.to_s
    query = URI.decode_www_form(uri.query.to_s).to_h
    if (id = path[%r{/jbi/([^/?#]+)}, 1]).present?
      "jbi:#{id}"
    elsif (id = path[%r{/jbn/([^/?#]+)}, 1]).present?
      "jbn:#{id}"
    elsif (id = path[%r{/jb/([^/?#]+)}, 1]).present?
      "jb:#{id}"
    elsif query["uaid"].present?
      "uaid:#{query['uaid']}"
    else
      fallback
    end
  rescue URI::InvalidURIError
    "#{company_raw}#{title}"
  end
end
