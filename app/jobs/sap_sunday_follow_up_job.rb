class SapSundayFollowUpJob < ApplicationJob
  def perform
    SapLead::SundayFollowUp.new.run
  end
end
