module Pipeline
  class SendTargets
    def initialize(campaign)
      @campaign = campaign
    end

    def ids
      admin_id = @campaign.admin_id
      captcha_ng_customer_ids = Call.where(call_type: "form", status: "CAPTCHA NG").distinct.select(:customer_id)
      rows = Customer.with_business(@campaign.business)
        .with_real_contact_url
        .visible_on_form_send_list
        .where.not(id: captcha_ng_customer_ids)
        .deliverable_for(nil, admin_id)
        .where.not(id: group_success_ids)
        .where.not(id: cross_success_ids)
        .pluck(:id, :contact_url)
      ids = rows.reject { |_, contact_url| Customer.blocked_url?(contact_url) }.map(&:first)
      return ids unless @campaign.exclude_existing_clients?

      ids - ClientExclusion.new.matching_ids(ids)
    end

    private

    def group_success_ids
      since = 30.days.ago
      keys = Campaign.in_group(@campaign.group).map(&:key)
      batches = FormSubmissionBatch.where(campaign_key: keys).where("started_at >= ?", since)
      success_customer_ids(batches)
    end

    def cross_success_ids
      Call.form_submissions
        .where(status: "自動送信成功")
        .where("calls.created_at >= ?", Campaign.cross_send_interval.ago)
        .select(:customer_id)
    end

    def success_customer_ids(batches)
      ids = []
      batches.find_each do |batch|
        customer_ids = batch.parsed_customer_ids
        next if customer_ids.empty?

        ids.concat(
          Call.form_submissions
            .where(status: "自動送信成功", customer_id: customer_ids)
            .where("calls.created_at >= ?", batch.started_at)
            .pluck(:customer_id)
        )
      end
      ids.uniq
    end
  end
end
