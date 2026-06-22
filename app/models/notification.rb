class Notification < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :client, optional: true
  belongs_to :notifiable, polymorphic: true, optional: true

  validates :type, presence: true
  validates :status, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :for_admin, -> { where(client_id: nil) }
  scope :for_client, ->(client_id) { where(client_id: client_id) }

  def self.create_for_serp!(run:, client_id: nil)
    create!(
      type: 'SerpEnrichment',
      status: run.status,
      total_count: run.target_count.to_i,
      success_count: run.summary_json['done_count'].to_i,
      error_count: run.summary_json['error_count'].to_i,
      client_id: client_id,
      notifiable: run,
      message: generate_serp_message(run)
    )
  end

  def self.create_for_form_submission!(batch:)
    create!(
      type: 'FormSubmission',
      status: batch.status,
      total_count: batch.total_count.to_i,
      success_count: batch.success_count.to_i,
      error_count: batch.failure_count.to_i,
      client_id: batch.client_id,
      notifiable: batch,
      message: generate_form_submission_message(batch)
    )
  end

  def self.create_for_form_detection!(batch:, client_id: nil)
    create!(
      type: 'FormDetection',
      status: batch.status,
      total_count: batch.total_count.to_i,
      success_count: batch.success_count.to_i,
      error_count: batch.failure_count.to_i,
      client_id: batch.client_id,
      notifiable: batch,
      message: generate_form_detection_message(batch)
    )
  end

  def mark_as_read!
    update!(read_at: Time.current)
  end

  def read?
    read_at.present?
  end

  def unread?
    !read?
  end

  private

  def self.generate_serp_message(run)
    done_count = run.summary_json['done_count'].to_i
    error_count = run.summary_json['error_count'].to_i
    "SERP実行完了: 実行#{run.target_count}件, 成功#{done_count}件, エラー#{error_count}件"
  end

  def self.generate_form_submission_message(batch)
    "フォーム送信完了: 実行#{batch.total_count.to_i}件, 成功#{batch.success_count.to_i}件, エラー#{batch.failure_count.to_i}件"
  end

  def self.generate_form_detection_message(batch)
    "フォーム検出完了: 実行#{batch.total_count.to_i}件, 成功#{batch.success_count.to_i}件, エラー#{batch.failure_count.to_i}件"
  end
end