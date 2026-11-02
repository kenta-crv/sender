module SapLead
  class GoogleSheet
    SCOPE = "https://www.googleapis.com/auth/spreadsheets".freeze

    def initialize(service: nil, credentials_path: ENV["SAP_REPORT_SHEETS_CREDENTIALS"])
      @service = service
      @credentials_path = credentials_path
    end

    def append_unless_present(spreadsheet_id, row)
      service = @service || build_service
      title = service.sheet_title(spreadsheet_id)
      column_a = service.column_a(spreadsheet_id, title)
      return :skipped if column_a.any? { |value| value.to_s == row.first.to_s }

      service.append(spreadsheet_id, title, row)
      :appended
    end

    private

    def build_service
      raise "SAP_REPORT_SHEETS_CREDENTIALS が未設定です" if @credentials_path.blank?
      raise "SAPレポートの鍵ファイルがありません" unless File.exist?(@credentials_path)

      GoogleSheetApi.new(@credentials_path)
    end
  end

  class GoogleSheetApi
    def initialize(credentials_path)
      require "google/apis/sheets_v4"
      require "googleauth"
      @service = Google::Apis::SheetsV4::SheetsService.new
      @service.authorization = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: File.open(credentials_path),
        scope: GoogleSheet::SCOPE
      )
    end

    def sheet_title(spreadsheet_id)
      sheet = @service.get_spreadsheet(spreadsheet_id).sheets.first
      raise "スプレッドシートにシートがありません" if sheet.nil?

      sheet.properties.title
    end

    def column_a(spreadsheet_id, title)
      response = @service.get_spreadsheet_values(spreadsheet_id, "#{quote(title)}!A:A")
      Array(response.values).map { |line| line.first }
    end

    def append(spreadsheet_id, title, row)
      body = Google::Apis::SheetsV4::ValueRange.new(values: [row])
      @service.append_spreadsheet_value(
        spreadsheet_id,
        "#{quote(title)}!A:Z",
        body,
        value_input_option: "USER_ENTERED"
      )
    end

    private

    def quote(title)
      "'#{title.to_s.gsub("'", "''")}'"
    end
  end
end
