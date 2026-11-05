if defined?(Sidekiq::Cron)
  Sidekiq::Cron::Job.create(
    name: 'Recording Cleanup - daily at 3am',
    cron: '0 3 * * *',
    class: 'RecordingCleanupJob'
  )

  # cron の末尾でタイムゾーンを指定し、サーバーの時刻設定に依存しない。
  Sidekiq::Cron::Job.create(
    name: 'SAP Kyujinbox scrape - daily at 2:00',
    cron: '0 2 * * * Asia/Tokyo',
    class: 'KyujinboxScrapeJob'
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP lead resolve and register - Saturday at 4:00',
    cron: '0 4 * * 6 Asia/Tokyo',
    class: 'SapLeadResolveJob'
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP sunday url and form detect - Sunday at 4:00',
    cron: '0 4 * * 0 Asia/Tokyo',
    class: 'SapSundayFollowUpJob'
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP weekly send - Monday at 9:00',
    cron: '0 9 * * 1 Asia/Tokyo',
    class: 'SapWeeklySendJob'
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP weekly report - Friday at 22:00',
    cron: '0 22 * * 5 Asia/Tokyo',
    class: 'SapWeeklyReportJob'
  )
end
