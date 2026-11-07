if defined?(Sidekiq::Cron)
  # sidekiq-cron 1.9 は ActiveJob を自動判別できず perform_async で落ちる。active_job: true が必要。
  Sidekiq::Cron::Job.create(
    name: 'Recording Cleanup - daily at 3am',
    cron: '0 3 * * *',
    class: 'RecordingCleanupJob',
    active_job: true
  )

  # cron の末尾でタイムゾーンを指定し、サーバーの時刻設定に依存しない。
  Sidekiq::Cron::Job.create(
    name: 'SAP Kyujinbox scrape - daily at 2:00',
    cron: '0 2 * * * Asia/Tokyo',
    class: 'KyujinboxScrapeJob',
    active_job: true
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP lead resolve and register - Saturday at 4:00',
    cron: '0 4 * * 6 Asia/Tokyo',
    class: 'SapLeadResolveJob',
    active_job: true
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP sunday url and form detect - Sunday at 4:00',
    cron: '0 4 * * 0 Asia/Tokyo',
    class: 'SapSundayFollowUpJob',
    active_job: true
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP weekly send - Monday at 9:00',
    cron: '0 9 * * 1 Asia/Tokyo',
    class: 'SapWeeklySendJob',
    active_job: true
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP weekly report - Friday at 22:00',
    cron: '0 22 * * 5 Asia/Tokyo',
    class: 'SapWeeklyReportJob',
    active_job: true
  )
end
