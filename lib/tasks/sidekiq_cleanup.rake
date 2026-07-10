# frozen_string_literal: true

namespace :sidekiq do
  desc "共有Redisに残った他アプリ由来ジョブ（ExpireTimedOutInterviewsJob等）を削除"
  task purge_foreign_jobs: :environment do
    require "sidekiq/api"

    foreign_classes = %w[ExpireTimedOutInterviewsJob EmailVerificationWorker]
    foreign_cron_names = %w[expire_timed_out_interviews "Email Verification - every 10 minutes"]

    deleted = { cron: 0, retry: 0, scheduled: 0, dead: 0, default: 0 }

    if defined?(Sidekiq::Cron::Job)
      Sidekiq::Cron::Job.all.each do |job|
        next unless foreign_classes.include?(job.klass) || foreign_cron_names.include?(job.name)

        job.destroy
        deleted[:cron] += 1
        puts "cron削除: #{job.name} (#{job.klass})"
      end
    end

    Sidekiq::RetrySet.new.each do |job|
      next unless foreign_classes.include?(job.klass)

      job.delete
      deleted[:retry] += 1
    end

    Sidekiq::ScheduledSet.new.each do |job|
      next unless foreign_classes.include?(job.klass)

      job.delete
      deleted[:scheduled] += 1
    end

    Sidekiq::DeadSet.new.each do |job|
      next unless foreign_classes.include?(job.klass)

      job.delete
      deleted[:dead] += 1
    end

    Sidekiq::Queue.new("default").each do |job|
      next unless foreign_classes.include?(job.klass)

      job.delete
      deleted[:default] += 1
    end

    puts "削除完了: #{deleted.inspect}"
    puts "残りcron: #{Sidekiq::Cron::Job.all.map(&:name).join(', ')}" if defined?(Sidekiq::Cron::Job)
  end
end
