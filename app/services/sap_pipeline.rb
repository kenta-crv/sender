module SapPipeline
  class << self
    def config
      YAML.load_file(Rails.root.join("config/sap_pipeline.yml")).deep_symbolize_keys
    end

    def admin_id
      integer_env("SAP_SEND_ADMIN_ID")
    end

    def submission_id
      integer_env("SAP_SEND_SUBMISSION_ID")
    end

    def spreadsheet_id
      config[:spreadsheet_id].presence
    end

    private

    def integer_env(key)
      value = ENV[key].presence
      return if value.blank?
      Integer(value, exception: false)
    end
  end
end
