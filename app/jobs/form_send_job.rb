class FormSendJob < ApplicationJob
  queue_as :form_submission

  retry_on StandardError, attempts: 0

  def perform(batch_id, customer_id)
    Rails.logger.info(
      "[FormSendJob] 開始: " \
      "batch_id=#{batch_id}, " \
      "customer_id=#{customer_id}, " \
      "thread=#{Thread.current.object_id}, " \
      "time=#{Time.current.strftime('%H:%M:%S')}"
    )

    batch = FormSubmissionBatch.find_by(id: batch_id)

    return unless batch
    return if batch.status == 'cancelled'

    customer = Customer.find_by(id: customer_id)

    unless customer
      batch.record_result!(
        customer_id,
        success: false,
        message: '顧客が見つかりません'
      )
      return
    end

    sender = nil

    begin
      sender_info = build_sender_info(batch, customer)

      sender = FormSender.new(
        debug: true,
        headless: true,
        save_to_db: true,
        sender_info: sender_info,
        skip_detection: true
      )

      result = sender.send_to_customer(customer)

      success = result[:status] == '自動送信成功'

      batch.record_result!(
        customer_id,
        success: success,
        message: "#{result[:status]}: #{result[:message]}"
      )

    rescue StandardError => e
      Rails.logger.error(
        "[FormSendJob] customer_id=#{customer_id} エラー: #{e.message}"
      )

      batch.record_result!(
        customer_id,
        success: false,
        message: e.message
      )

    ensure
      sender&.teardown_driver rescue nil
    end
  end

  private

  def build_sender_info(batch, customer)
    submission = batch.submission

    return nil unless submission

    info = {}

    info[:company] = submission.company if submission.company.present?

    if submission.person.present?
      info[:name] = submission.person

      parts = submission.person.strip.split(/[\s　]+/, 2)

      if parts.size == 2
        info[:name_sei] = parts[0]
        info[:name_mei] = parts[1]
      end
    end

    if submission.person_kana.present?
      kana = submission.person_kana.strip

      info[:name_kana] = kana

      parts = kana.split(/[\s　]+/, 2)

      if parts.size == 2
        info[:name_kana_sei] = parts[0]
        info[:name_kana_mei] = parts[1]
      end

      hira = kana.tr('ァ-ヶ', 'ぁ-ゖ')

      info[:name_hira] = hira

      hira_parts = hira.split(/[\s　]+/, 2)

      if hira_parts.size == 2
        info[:name_hira_sei] = hira_parts[0]
        info[:name_hira_mei] = hira_parts[1]
      end
    end

    if submission.tel.present?
      tel = submission.tel.strip

      info[:tel] = tel
      info[:tel_no_hyphen] = tel.gsub('-', '')

      tel_parts = tel.split('-')

      if tel_parts.size == 3
        info[:tel1] = tel_parts[0]
        info[:tel2] = tel_parts[1]
        info[:tel3] = tel_parts[2]
      end
    end

    if submission.address.present?
      addr = submission.address.strip

      info[:address] = addr

      if addr =~ /\A((?:北海道|(?:東京|大阪|京都)府|.{2,3}県))(.*)/
        info[:prefecture] = $1

        rest = $2

        if rest =~ /\A(.+?[市区町村郡])(.*)/
          info[:address_city] = $1
          info[:address_street] = $2
        else
          info[:address_city] = rest
          info[:address_street] = rest
        end
      end
    end

    info[:email] = submission.email if submission.email.present?

    ri_plus_options = { host: 'ri-plus.jp', protocol: 'https', port: nil }

    tracking = ClickTrackingLink.create!(
      customer: customer,
      client: batch.client,
      admin: batch.admin,
      target_url: submission.url
    )

    tracking_link =
      Rails.application.routes.url_helpers.click_tracking_url(
        tracking.token,
        ri_plus_options
      )

    if submission.content.present?
      info[:message] = <<~TEXT
        #{submission.content}

        詳細はこちら
        #{tracking_link}
      TEXT
    end

    info[:url] = submission.url if submission.url.present?

    info
  end
end