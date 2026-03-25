class Payment < ApplicationRecord
  belongs_to :client
  belongs_to :campaign, optional: true

  enum status: { pending: "pending", succeeded: "succeeded", failed: "failed" }

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :payjp_charge_id, presence: true
  validates :status, presence: true

  def amount_in_yen
    amount
  end

  def formatted_amount
    "¥#{amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse}"
  end
end

