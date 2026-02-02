# frozen_string_literal: true

require "nokogiri"

class CompanyInfoExtractor
  TEL_REGEX = /0\d{1,4}-\d{1,4}-\d{3,4}/

  def initialize(html, customer:)
    @doc = Nokogiri::HTML(html)
    @customer = customer
  end

  def extract
    {
      company: extract_company,
      tel: extract_tel,
      address: extract_address,
      contact_url: extract_contact_url
    }
  end

  private

  def extract_company
    from_profile || from_footer || from_regex || @customer.company
  end

  def from_profile
    text = @doc.text
    text[/会社名[:：]?\s*(.+)/, 1]&.strip
  end

  def from_footer
    footer = @doc.at("footer")
    return if footer.nil?
    footer.text[/会社名[:：]?\s*(.+)/, 1]&.strip
  end

  def from_regex
    @doc.text[/(株式会社|有限会社|合同会社).+?/]
  end

  def extract_tel
    @doc.text[TEL_REGEX]
  end

  def extract_address
    addr = @customer.address
    @doc.text.include?(addr) ? addr : nil
  end

  def extract_contact_url
    @doc.css("a").each do |a|
      href = a["href"]
      next if href.blank?
      return href if href.match?(/contact|お問い合わせ|問合せ/)
    end
    nil
  end
end
