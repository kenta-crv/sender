# frozen_string_literal: true

class DeliveryOptOut < ApplicationRecord
  belongs_to :customer
  belongs_to :client
end
