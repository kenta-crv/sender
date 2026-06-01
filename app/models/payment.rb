class Payment < ApplicationRecord
  belongs_to :client

  enum status: { pending: "pending", succeeded: "succeeded", failed: "failed" }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true

  def amount_in_yen
    amount
  end

  def formatted_amount
    "¥#{amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse}"
  end
end