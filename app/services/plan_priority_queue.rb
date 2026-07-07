# frozen_string_literal: true

# Sidekiq キュー優先順位: Enterprise → Standard → Trial → Admin
module PlanPriorityQueue
  TIERS = %i[enterprise standard trial admin].freeze

  JOB_TYPES = %i[form_submission form_detection serp_enrichment].freeze

  PLAN_LABELS = {
    "enterprise" => "エンタープライズ",
    "standard" => "スタンダード",
    "trial" => "トライアル"
  }.freeze

  class << self
    def tier_for(client:, admin: false)
      return :admin if admin

      plan = client&.subscription_plan.to_s
      return :trial if plan == "trial" || client&.on_trial?
      return :enterprise if plan == "enterprise"
      return :standard if plan == "standard"

      :admin
    end

    def queue_for(job_type, client:, admin: false)
      tier = tier_for(client: client, admin: admin)
      :"#{job_type}_#{tier}"
    end

    def plan_label(client)
      PLAN_LABELS[client&.subscription_plan.to_s] || "未契約"
    end

    def wait_notice_for(client:, admin: false)
      return nil if admin

      plan_label = plan_label(client)
      "処理はプラン優先順位（エンタープライズ → スタンダード → トライアル → 管理者）に従って実行されます。" \
        "現在のプラン（#{plan_label}）では、上位プランの処理が優先される場合に待機時間が発生することがあります。"
    end

    def enqueue_form_send(batch_id, customer_id, client:, admin: false)
      queue = queue_for(:form_submission, client: client, admin: admin)
      FormSendJob.set(queue: queue).perform_later(batch_id, customer_id)
    end

    def enqueue_contact_detect(customer_id, batch_id, client:, admin: false)
      queue = queue_for(:form_detection, client: client, admin: admin)
      ContactUrlDetectJob.set(queue: queue).perform_later(customer_id, batch_id)
    end
  end
end
