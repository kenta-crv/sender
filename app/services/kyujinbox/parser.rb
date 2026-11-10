module Kyujinbox
  class Parser
    def self.extract(html, page_url:)
      doc = Nokogiri::HTML(html)
      postings = doc.css("section.p-result_card").filter_map { |card| posting_from(card, page_url) }
      next_href = doc.at_css("a.c-pager_btn--next")&.[]("href")
      next_url = next_href.present? ? URI.join(page_url, next_href).to_s : nil
      Page.new(postings: postings, next_url: next_url)
    end

    def self.posting_from(card, page_url)
      company = Kyujinbox.base_company_name(card.at_css("p.p-result_companyName, p.p-result_company")&.text.to_s.squish)
      return nil if company.blank?
      return nil unless Kyujinbox.legal_entity?(company)

      href = card.at_css("a.p-result_title_link")&.[]("href")
      posting_url = href.present? ? URI.join(page_url, href).to_s : ""
      title = card.at_css("span.p-result_name")&.text.to_s.squish
      area = card.at_css("li.p-result_area")&.text.to_s.squish
      employ_type = card.at_css("li.p-result_employType")&.text.to_s.squish
      updated_text = card.at_css("p.p-result_updatedAt_hyphen")&.text.to_s.squish
      source_text = card.at_css("p.p-result_source")&.text.to_s.squish

      posting = Posting.new(
        company_raw: company,
        company_clean: Kyujinbox.clean_company(company),
        title: title,
        area: area,
        employ_type: employ_type,
        posting_url: posting_url,
        job_key: Kyujinbox.job_key_for(posting_url, company, title),
        updated_text: updated_text,
        source_text: source_text
      )
      return nil if Kyujinbox.excluded?(posting)

      posting
    end
    private_class_method :posting_from
  end
end
