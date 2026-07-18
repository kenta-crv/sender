require 'csv'

class CustomerImportService
  LEGAL_ENTITY_PATTERN = /株式会社|有限会社|合同会社|一般社団法人|一般財団法人|社会福祉法人|医療法人|学校法人|(株)|（株）|(有)|（有）|(同)|（同）/.freeze

  COLUMN_MAP = {
    tel:         %w[電話番号 tel],
    address:     %w[住所 address],
    url:         %w[HP\ URL url],
    email:       %w[メールアドレス email],
    business:    %w[業種 business],
    genre:       %w[職種 genre],
    contact_url: %w[問い合わせURL contact_url],
    capital:     %w[資本金 capital],
    establish:   %w[設立 establish],
    ceo:         %w[代表者 ceo],
    people:      %w[従業員数 people]
  }.freeze

  COMPANY_KEYS = %w[会社名 company].freeze

  def initialize(overwrite_blank: false, client_id: nil)
    @overwrite_blank = overwrite_blank
    @client_id = client_id
  end

  def call(file_path: nil, csv_content: nil)
    import_count = 0
    error_count = 0
    error_samples = []

    each_csv_row(file_path: file_path, csv_content: csv_content) do |row|
      company_name = company_name_from(row)

      if company_name.blank?
        error_count += 1
        error_samples << { company: nil, errors: ['会社名(company)が空です'] }
        next
      end

      unless company_name.match?(LEGAL_ENTITY_PATTERN)
        error_count += 1
        error_samples << { company: company_name, errors: ['法人敬称（株式会社など）が含まれていません'] }
        next
      end

      customer = Customer.find_or_initialize_by(company: company_name)
      customer.assign_attributes(attributes_from(row))
      customer.client_id = @client_id if @client_id.present?

      if customer.save
        import_count += 1
      else
        error_count += 1
        error_samples << { company: company_name, errors: customer.errors.full_messages }
        Rails.logger.error("IMPORT ERROR: #{customer.errors.full_messages} | ROW: #{row.to_h}")
      end
    end

    {
      import_count: import_count,
      error_count: error_count,
      error_samples: error_samples
    }
  end

  private

  def company_name_from(row)
    COMPANY_KEYS.lazy.map { |key| row[key] }.find(&:present?)&.to_s&.strip
  end

  def attributes_from(row)
    headers = row.headers.map(&:to_s)

    COLUMN_MAP.each_with_object({}) do |(attr, keys), attrs|
      key = keys.find { |candidate| headers.include?(candidate) }
      next unless key

      value = row[key].to_s.strip

      if @overwrite_blank
        attrs[attr] = value
      elsif value.present?
        attrs[attr] = value
      end
    end
  end

  def each_csv_row(file_path:, csv_content:)
    if csv_content.present?
      CSV.parse(csv_content, headers: true) do |row|
        yield row
      end
      return
    end

    CSV.foreach(file_path, headers: true) do |row|
      yield row
    end
  end
end
