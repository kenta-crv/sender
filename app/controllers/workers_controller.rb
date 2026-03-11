class WorkersController < ApplicationController
  before_action :authenticate_worker!

  def show
    @worker = Worker.find(params[:id])
    @stats  = @worker.stats_summary

    # Submission一覧（手動作業ありのみ）
    @submissions = Submission.where.not(manual: nil)

    # 各Submissionごとの失敗件数を集計
    @submission_failures = @submissions.each_with_object({}) do |submission, hash|
      failure_count = submission.form_submission_batches.sum(:failure_count)
      hash[submission.id] = failure_count
    end
  end
end