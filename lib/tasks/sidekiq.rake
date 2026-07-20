# frozen_string_literal: true

# Sidekiq 一時停止 / 再開（Redis キューは保持される）
#
# 使い方:
#   RAILS_ENV=production bundle exec rake sidekiq:status
#   RAILS_ENV=production bundle exec rake sidekiq:quiet   # 新規取得停止（処理中は完了待ち）
#   RAILS_ENV=production bundle exec rake sidekiq:stop    # プロセス停止（キュー残る）
#   # DB切替後に Sidekiq プロセスを通常どおり起動すれば再開

namespace :sidekiq do
  desc "Show Sidekiq queue sizes and process busy counts"
  task status: :environment do
    require "sidekiq/api"

    puts "queues:"
    Sidekiq::Queue.all.each do |q|
      puts "  #{q.name}: #{q.size}"
    end
    puts "retry: #{Sidekiq::RetrySet.new.size}"
    puts "scheduled: #{Sidekiq::ScheduledSet.new.size}"
    puts "dead: #{Sidekiq::DeadSet.new.size}"
    puts "processes:"
    Sidekiq::ProcessSet.new.each do |process|
      puts "  #{process['hostname']}:#{process['pid']} busy=#{process['busy']} quiet=#{process['quiet']}"
    end
  end

  desc "Quiet Sidekiq processes (finish current jobs, take no new work)"
  task quiet: :environment do
    require "sidekiq/api"

    count = 0
    Sidekiq::ProcessSet.new.each do |process|
      process.quiet!
      count += 1
      puts "quieted #{process['hostname']}:#{process['pid']}"
    end
    puts "quieted #{count} process(es). Redis queues are preserved."
  end

  desc "Ask Sidekiq processes to stop after finishing current jobs"
  task stop: :environment do
    require "sidekiq/api"

    count = 0
    Sidekiq::ProcessSet.new.each do |process|
      process.stop!
      count += 1
      puts "stop signal -> #{process['hostname']}:#{process['pid']}"
    end
    puts "signaled #{count} process(es). Redis queues remain until workers restart."
  end
end
