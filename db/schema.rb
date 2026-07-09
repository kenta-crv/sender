# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_07_09_140000) do

  create_table "admins", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
  end

  create_table "call_batches", force: :cascade do |t|
    t.string "name"
    t.integer "total_count", default: 0
    t.integer "processed_count", default: 0
    t.integer "success_count", default: 0
    t.integer "failure_count", default: 0
    t.integer "transferred_count", default: 0
    t.string "status", default: "pending"
    t.text "customer_ids"
    t.text "error_log", default: "[]"
    t.integer "concurrent_lines", default: 3
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "worker_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["status"], name: "index_call_batches_on_status"
    t.index ["worker_id"], name: "index_call_batches_on_worker_id"
  end

  create_table "calls", force: :cascade do |t|
    t.string "status"
    t.string "comment"
    t.integer "customer_id"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "call_type", default: "phone"
    t.integer "worker_id"
    t.string "twilio_call_sid"
    t.string "flow_phase"
    t.text "speech_result"
    t.string "speech_category"
    t.float "speech_confidence"
    t.datetime "started_at"
    t.datetime "answered_at"
    t.datetime "ended_at"
    t.integer "duration"
    t.string "recording_url"
    t.string "recording_sid"
    t.string "transferred_to"
    t.string "conference_sid"
    t.string "twilio_status"
    t.integer "call_batch_id"
    t.string "stream_sid"
    t.datetime "speech_detected_at"
    t.index ["call_batch_id"], name: "index_calls_on_call_batch_id"
    t.index ["customer_id"], name: "index_calls_on_customer_id"
    t.index ["twilio_call_sid"], name: "index_calls_on_twilio_call_sid"
  end

  create_table "click_logs", force: :cascade do |t|
    t.integer "click_tracking_link_id", null: false
    t.string "ip"
    t.text "user_agent"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["click_tracking_link_id"], name: "index_click_logs_on_click_tracking_link_id"
  end

  create_table "click_tracking_links", force: :cascade do |t|
    t.string "token", null: false
    t.integer "customer_id"
    t.integer "client_id"
    t.integer "admin_id"
    t.text "target_url"
    t.integer "clicked_count", default: 0, null: false
    t.datetime "last_clicked_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "submission_id"
    t.integer "form_submission_batch_id"
    t.index ["admin_id"], name: "index_click_tracking_links_on_admin_id"
    t.index ["client_id"], name: "index_click_tracking_links_on_client_id"
    t.index ["customer_id"], name: "index_click_tracking_links_on_customer_id"
    t.index ["form_submission_batch_id"], name: "index_click_tracking_links_on_form_submission_batch_id"
    t.index ["submission_id"], name: "index_click_tracking_links_on_submission_id"
    t.index ["token"], name: "index_click_tracking_links_on_token", unique: true
  end

  create_table "clients", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "company"
    t.string "name"
    t.string "tel"
    t.string "address"
    t.string "url"
    t.string "domain", default: "", null: false
    t.string "api_key", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "subscription_plan", default: "trial"
    t.string "subscription_status", default: "active"
    t.datetime "trial_ends_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "stripe_customer_id"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "registration_ip"
    t.boolean "registration_flagged", default: false, null: false
    t.string "stripe_payment_method_id"
    t.string "card_fingerprint"
    t.index ["card_fingerprint"], name: "index_clients_on_card_fingerprint"
    t.index ["confirmation_token"], name: "index_clients_on_confirmation_token", unique: true
    t.index ["email"], name: "index_clients_on_email", unique: true
    t.index ["registration_ip"], name: "index_clients_on_registration_ip"
    t.index ["reset_password_token"], name: "index_clients_on_reset_password_token", unique: true
    t.index ["stripe_customer_id"], name: "index_clients_on_stripe_customer_id", unique: true
    t.index ["subscription_plan"], name: "index_clients_on_subscription_plan"
    t.index ["subscription_status"], name: "index_clients_on_subscription_status"
  end

  create_table "columns", force: :cascade do |t|
    t.string "title"
    t.string "file"
    t.string "choice"
    t.string "keyword"
    t.string "description"
    t.string "status", default: "draft"
    t.text "body"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "genre"
    t.string "code"
    t.string "article_type", default: "cluster", null: false
    t.integer "parent_id"
    t.integer "cluster_limit"
    t.index ["article_type"], name: "index_columns_on_article_type"
    t.index ["code"], name: "index_columns_on_code", unique: true
    t.index ["parent_id"], name: "index_columns_on_parent_id"
  end

  create_table "contracts", force: :cascade do |t|
    t.string "company"
    t.string "name"
    t.string "tel"
    t.string "email"
    t.string "address"
    t.string "url"
    t.string "service"
    t.string "period"
    t.string "message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "customer_update_logs", force: :cascade do |t|
    t.integer "customer_id", null: false
    t.integer "worker_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["customer_id"], name: "index_customer_update_logs_on_customer_id"
    t.index ["worker_id"], name: "index_customer_update_logs_on_worker_id"
  end

  create_table "customers", force: :cascade do |t|
    t.string "company"
    t.string "tel"
    t.string "address"
    t.string "email"
    t.string "url"
    t.string "business"
    t.string "genre"
    t.string "contact_url"
    t.string "fobbiden"
    t.string "status"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "serp_status"
    t.integer "client_id"
    t.string "unsubscribe_token"
    t.index ["client_id"], name: "index_customers_on_client_id"
    t.index ["unsubscribe_token"], name: "index_customers_on_unsubscribe_token", unique: true
  end

  create_table "delivery_opt_outs", force: :cascade do |t|
    t.integer "customer_id", null: false
    t.integer "client_id", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["client_id"], name: "index_delivery_opt_outs_on_client_id"
    t.index ["customer_id", "client_id"], name: "index_delivery_opt_outs_on_customer_id_and_client_id", unique: true
    t.index ["customer_id"], name: "index_delivery_opt_outs_on_customer_id"
  end

  create_table "extract_trackings", force: :cascade do |t|
    t.string "industry", null: false
    t.integer "total_count", default: 0, null: false
    t.integer "success_count", default: 0, null: false
    t.integer "failure_count", default: 0, null: false
    t.string "status", null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["industry", "id"], name: "index_extract_trackings_on_industry_and_id"
    t.index ["industry"], name: "index_extract_trackings_on_industry"
  end

  create_table "fax_deliveries", force: :cascade do |t|
    t.integer "customer_id", null: false
    t.string "media_url"
    t.string "status"
    t.string "twilio_sid"
    t.integer "retry_count", default: 0
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["customer_id"], name: "index_fax_deliveries_on_customer_id"
    t.index ["status"], name: "index_fax_deliveries_on_status"
    t.index ["twilio_sid"], name: "index_fax_deliveries_on_twilio_sid"
  end

  create_table "fax_logs", force: :cascade do |t|
    t.string "fax_sid"
    t.string "to_number"
    t.string "media_url"
    t.string "status"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "form_detection_batches", force: :cascade do |t|
    t.integer "total_count"
    t.integer "processed_count"
    t.integer "success_count"
    t.integer "error_count"
    t.integer "client_id"
    t.string "status"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.text "customer_ids"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "failure_count", default: 0
  end

  create_table "form_submission_batches", force: :cascade do |t|
    t.integer "total_count", default: 0
    t.integer "processed_count", default: 0
    t.integer "success_count", default: 0
    t.integer "failure_count", default: 0
    t.string "status", default: "pending"
    t.integer "current_customer_id"
    t.text "customer_ids"
    t.text "error_log"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "submission_id"
    t.integer "client_id"
    t.integer "admin_id"
    t.index ["admin_id"], name: "index_form_submission_batches_on_admin_id"
    t.index ["client_id"], name: "index_form_submission_batches_on_client_id"
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "funnel_events", force: :cascade do |t|
    t.string "page", null: false
    t.string "event_type", null: false
    t.integer "time_spent_seconds"
    t.string "ip"
    t.text "user_agent"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "click_tracking_link_id"
    t.index ["click_tracking_link_id"], name: "index_funnel_events_on_click_tracking_link_id"
    t.index ["created_at"], name: "index_funnel_events_on_created_at"
    t.index ["event_type"], name: "index_funnel_events_on_event_type"
    t.index ["page"], name: "index_funnel_events_on_page"
  end

  create_table "monthly_usage_logs", force: :cascade do |t|
    t.integer "client_id", null: false
    t.string "month", null: false
    t.integer "sent_count", default: 0, null: false
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "serp_api_limit", default: 0, null: false
    t.integer "serp_api_used", default: 0, null: false
    t.integer "form_detection_limit", default: 0, null: false
    t.integer "form_detection_used", default: 0, null: false
    t.index ["client_id", "month"], name: "index_monthly_usage_logs_on_client_id_and_month", unique: true
    t.index ["client_id"], name: "index_monthly_usage_logs_on_client_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.string "type"
    t.string "status"
    t.integer "total_count"
    t.integer "success_count"
    t.integer "error_count"
    t.integer "client_id"
    t.datetime "read_at"
    t.string "notifiable_type"
    t.integer "notifiable_id"
    t.text "message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["client_id"], name: "index_notifications_on_client_id"
    t.index ["created_at"], name: "index_notifications_on_created_at"
    t.index ["notifiable_id"], name: "index_notifications_on_notifiable_id"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable_type_and_notifiable_id"
    t.index ["notifiable_type"], name: "index_notifications_on_notifiable_type"
    t.index ["read_at"], name: "index_notifications_on_read_at"
  end

  create_table "payments", force: :cascade do |t|
    t.integer "client_id", null: false
    t.integer "amount", null: false
    t.string "status", default: "pending", null: false
    t.text "description"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "stripe_payment_intent_id"
    t.index ["client_id"], name: "index_payments_on_client_id"
    t.index ["status"], name: "index_payments_on_status"
    t.index ["stripe_payment_intent_id"], name: "index_payments_on_stripe_payment_intent_id", unique: true
  end

  create_table "problems", force: :cascade do |t|
    t.string "company"
    t.string "email"
    t.string "body"
    t.string "photo"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
  end

  create_table "serp_enrichment_run_targets", force: :cascade do |t|
    t.integer "serp_enrichment_run_id", null: false
    t.integer "customer_id", null: false
    t.integer "position", default: 0, null: false
    t.string "company"
    t.string "before_serp_status"
    t.string "before_tel"
    t.text "before_address"
    t.string "before_url"
    t.string "before_contact_url"
    t.string "after_serp_status"
    t.string "after_tel"
    t.text "after_address"
    t.string "after_url"
    t.string "after_contact_url"
    t.string "result_status", default: "pending", null: false
    t.integer "candidate_count", default: 0, null: false
    t.string "selected_url"
    t.text "update_keys"
    t.text "error_message"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["customer_id"], name: "index_serp_enrichment_run_targets_on_customer_id"
    t.index ["result_status"], name: "index_serp_enrichment_run_targets_on_result_status"
    t.index ["serp_enrichment_run_id", "customer_id"], name: "index_serp_targets_on_run_and_customer"
    t.index ["serp_enrichment_run_id"], name: "index_serp_targets_on_run_id"
  end

  create_table "serp_enrichment_runs", force: :cascade do |t|
    t.string "run_id", null: false
    t.string "jid"
    t.string "status", default: "queued", null: false
    t.string "industry"
    t.integer "limit", default: 0, null: false
    t.integer "target_count", default: 0, null: false
    t.integer "serp_total", default: 0, null: false
    t.integer "serp_completed", default: 0, null: false
    t.integer "web_total", default: 0, null: false
    t.integer "web_completed", default: 0, null: false
    t.datetime "started_at"
    t.datetime "finished_at"
    t.text "error_message"
    t.text "summary_json"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.integer "client_id"
    t.index ["created_at"], name: "index_serp_enrichment_runs_on_created_at"
    t.index ["jid"], name: "index_serp_enrichment_runs_on_jid"
    t.index ["run_id"], name: "index_serp_enrichment_runs_on_run_id", unique: true
    t.index ["status"], name: "index_serp_enrichment_runs_on_status"
  end

  create_table "submissions", force: :cascade do |t|
    t.string "headline"
    t.string "company"
    t.string "person"
    t.string "person_kana"
    t.string "tel"
    t.string "fax"
    t.string "address"
    t.string "email"
    t.string "url"
    t.string "title"
    t.text "content"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "manual"
    t.integer "client_id"
    t.index ["client_id"], name: "index_submissions_on_client_id"
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "client_id", null: false
    t.string "plan_type", null: false
    t.string "status", default: "active", null: false
    t.datetime "trial_ends_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "stripe_subscription_id"
    t.index ["client_id"], name: "index_subscriptions_on_client_id"
    t.index ["plan_type"], name: "index_subscriptions_on_plan_type"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
  end

  create_table "twilio_configs", force: :cascade do |t|
    t.text "greeting_text", default: "お電話ありがとうございます。株式会社テストでございます。ご担当者様はいらっしゃいますでしょうか。"
    t.text "absent_text", default: "承知いたしました。不在とのことですね。改めてお電話させていただきます。失礼いたします。"
    t.text "inquiry_text", default: "ありがとうございます。本日は新しいサービスのご案内でお電話いたしました。"
    t.text "rejection_text", default: "承知いたしました。お時間いただきありがとうございました。失礼いたします。"
    t.text "transfer_text", default: "オペレーターにおつなぎいたします。"
    t.text "wait_text"
    t.string "operator_number"
    t.string "from_number"
    t.integer "no_answer_timeout", default: 7
    t.integer "speech_timeout", default: 3
    t.integer "gather_timeout", default: 5
    t.string "voice_language", default: "ja-JP"
    t.string "voice_name", default: "Polly.Mizuki"
    t.text "speech_hints", default: "不在にしております,いません,おりません,いないです,留守にしております,出かけております,席を外しております,ご用件は,結構です,必要ありません,間に合っております,いらないです,大丈夫です,お電話代わりました,お電話かわりました,電話代わりました,少々お待ちください,お待ちください,お待たせしました,担当の"
    t.boolean "recording_enabled", default: true
    t.integer "recording_min_duration", default: 60
    t.boolean "active", default: true
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.boolean "stream_mode_enabled", default: false
  end

  create_table "workers", force: :cascade do |t|
    t.string "user_name", default: "", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.index ["email"], name: "index_workers_on_email", unique: true
    t.index ["reset_password_token"], name: "index_workers_on_reset_password_token", unique: true
  end

  add_foreign_key "calls", "customers"
  add_foreign_key "click_logs", "click_tracking_links"
  add_foreign_key "click_tracking_links", "admins"
  add_foreign_key "click_tracking_links", "clients"
  add_foreign_key "click_tracking_links", "customers"
  add_foreign_key "click_tracking_links", "form_submission_batches"
  add_foreign_key "click_tracking_links", "submissions"
  add_foreign_key "customer_update_logs", "customers"
  add_foreign_key "customer_update_logs", "workers"
  add_foreign_key "customers", "clients"
  add_foreign_key "delivery_opt_outs", "clients"
  add_foreign_key "delivery_opt_outs", "customers"
  add_foreign_key "fax_deliveries", "customers"
  add_foreign_key "form_submission_batches", "admins"
  add_foreign_key "form_submission_batches", "clients"
  add_foreign_key "monthly_usage_logs", "clients"
  add_foreign_key "payments", "clients"
  add_foreign_key "serp_enrichment_run_targets", "serp_enrichment_runs"
  add_foreign_key "submissions", "clients"
  add_foreign_key "subscriptions", "clients"
end
