class ProblemMailer < ApplicationMailer
  default to: "info@j-work.jp"

  def report_email(problem)
    @problem = problem
    mail(
      to: "info@j-work.jp",
      from: @problem.email,
      subject: "【問題報告】#{@problem.company}様より"
    )
  end
end