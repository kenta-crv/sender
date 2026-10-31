class SapLeadRegisterJob < ApplicationJob
  def perform
    SapLead::Registrar.new.run
  end
end
