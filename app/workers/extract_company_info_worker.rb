require "json"
require 'open3'

class ExtractCompanyInfoWorker
  PYTHON_SCRIPT_PATH = Rails.root.join('extract_company_info', 'app.py').to_s
  PYTHON_VENV_PATH = Rails.root.join('extract_company_info', 'venv', 'bin', 'python').to_s
  PYTHON_EXECUTABLE = if File.exist?(PYTHON_VENV_PATH)
                        PYTHON_VENV_PATH
                      else
                        'python3'
                      end

  def perform(tracking_id)
    begin
      Rails.logger.info("ExtractCompanyInfoWorker: perform: start with TrackingID: #{tracking_id}")

      extract_tracking = ExtractTracking.find_by(id: tracking_id)
      return { success: 0, failure: 0, error: "Tracking not found" } unless extract_tracking

      # 本日の制限チェック
      daily_limit = ENV.fetch('EXTRACT_DAILY_LIMIT', '500').to_i
      today_total = ExtractTracking
                      .where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
                      .where.not(id: extract_tracking.id)
                      .sum(:total_count)
      
      today_remaining = [daily_limit - today_total, 0].max
      if today_remaining == 0 || extract_tracking.total_count > today_remaining
        extract_tracking.update_columns(status: "抽出失敗（制限超過）")
        return { success: 0, failure: 0, error: "Limit exceeded" }
      end
      
      limit_count = [extract_tracking.total_count, today_remaining].min
      customers_scope = Customer.where(status: "draft").where(tel: [nil, '', ' '])
      unless extract_tracking.industry == "全般" || extract_tracking.industry.blank?
        customers_scope = customers_scope.where(industry: extract_tracking.industry)
      end
      
      customers = customers_scope.limit(limit_count)
      success_count = 0
      failure_count = 0
      quota_exceeded = false
      customer_count = customers.count
      
      extract_tracking.update_columns(status: "抽出中")

      customers.each_with_index do |customer, index|
        command = [PYTHON_EXECUTABLE, PYTHON_SCRIPT_PATH]
        payload = {
          customer_id: customer.id.to_s,
          company: customer.company.to_s,
          location: customer.address.to_s,
          required_businesses: [],
          required_genre: []
        }
        
        begin
          stdout, stderr, status = execute_python_with_timeout(command, payload.to_json)
          
          # 【重要】Python側で何が起きたかログに詳細を出す
          Rails.logger.info("Python STDOUT: #{stdout}")
          Rails.logger.error("Python STDERR: #{stderr}") if stderr.present?
          
          response_json = nil
          begin
            response_json = JSON.parse(stdout.strip) if stdout.present?
          rescue JSON::ParserError
            response_json = nil
          end
          
          error_code = response_json&.dig("error", "code")

          if status&.success? && response_json && response_json['data']
            extracted_data = response_json['data']
            customer.update_columns(
              company: extracted_data['company'].presence || customer.company,
              tel: extracted_data['tel'].to_s,
              address: extracted_data['address'].to_s,
              first_name: extracted_data['first_name'].to_s,
              url: extracted_data['url'].to_s,
              contact_url: extracted_data['contact_url'].to_s,
              business: extracted_data['business'].to_s,
              genre: extracted_data['genre'].to_s,
              status: "extracted",
              updated_at: Time.current
            )
            success_count += 1
          else
            # 失敗原因をさらに細かく判定
            is_limit = error_code == "QUOTA_EXCEEDED" || stdout.to_s.include?("429") || stdout.to_s.include?("RESOURCE_EXHAUSTED") || stdout.to_s.include?("insufficient_quota")
            
            customer.update_columns(status: "failed", updated_at: Time.current)
            failure_count += 1
            
            if is_limit
              quota_exceeded = true
              extract_tracking.update_columns(status: "抽出停止（API制限）")
              Rails.logger.warn("API制限により停止しました。")
              break
            end
          end
          
          extract_tracking.update_columns(success_count: success_count, failure_count: failure_count)

        rescue => e
          Rails.logger.error("ExtractCompanyInfoWorker Error (ID: #{customer.id}): #{e.message}")
          customer.update_columns(status: "error", updated_at: Time.current)
          failure_count += 1
          extract_tracking.update_columns(failure_count: failure_count)
        end
        
        sleep(15) if !quota_exceeded && index < (customer_count - 1)
      end

      extract_tracking.update_columns(status: "抽出完了") unless quota_exceeded
      return { success: success_count, failure: failure_count }

    rescue => e
      Rails.logger.error("ExtractCompanyInfoWorker Fatal: #{e.message}")
      return { success: 0, failure: 0, error: e.message }
    end
  end

  def execute_python_with_timeout(command, stdin_data, timeout: 300)
    stdout_str = +""
    stderr_str = +""
    status = nil
    Open3.popen3({ "RAILS_ENV" => Rails.env, "PYTHONIOENCODING" => "utf-8" }, *command) do |stdin, stdout, stderr, wait_thr|
      begin
        stdin.write(stdin_data.encode("UTF-8"))
      rescue Errno::EPIPE
      ensure
        stdin.close
      end
      out_reader = Thread.new { stdout.each_line { |line| stdout_str << line } rescue nil }
      err_reader = Thread.new { stderr.each_line { |line| stderr_str << line } rescue nil }
      wait_thr.join(timeout)
      out_reader.join
      err_reader.join
      status = wait_thr.value
    end
    [stdout_str, stderr_str, status]
  end
end