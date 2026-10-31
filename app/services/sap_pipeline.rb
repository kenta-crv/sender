module SapPipeline
  class << self
    def config
      YAML.load_file(Rails.root.join("config/sap_pipeline.yml")).deep_symbolize_keys
    end

    def admin_id
      config.dig(:send, :admin_id).presence
    end

    def submission_id
      config.dig(:send, :submission_id).presence
    end

    def spreadsheet_id
      config[:spreadsheet_id].presence
    end
  end
end
