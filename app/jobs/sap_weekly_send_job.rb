class SapWeeklySendJob < ApplicationJob
  def perform
    SapLead::WeeklySend.new.run
  end
end
