# frozen_string_literal: true

class DeliveryOptOut < ApplicationRecord
  belongs_to :customer
  belongs_to :client, optional: true
  belongs_to :admin, optional: true

  validate :client_or_admin_presence

  private

  def client_or_admin_presence
    return if client_id.present? || admin_id.present?

    errors.add(:base, 'client_id または admin_id のいずれかが必要です')
  end
end
