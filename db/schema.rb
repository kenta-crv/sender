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

ActiveRecord::Schema.define(version: 2026_04_06_000001) do

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

  create_table "customers", force: :cascade do |t|
    t.string "company"
    t.string "name"
    t.string "tel"
    t.string "address"
    t.string "mobile"
    t.string "industry"
    t.string "email"
    t.string "url"
    t.string "business"
    t.string "genre"
    t.string "contact_url"
    t.string "fobbiden"
    t.string "status"
    t.string "remarks"
    t.datetime "created_at", precision: 6, null: false
    t.datetime "updated_at", precision: 6, null: false
    t.string "serp_status"
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
end
