class SapWeeklyReportJob < ApplicationJob
  def perform
    SapLead::WeeklyReport.new.run
  end
end
