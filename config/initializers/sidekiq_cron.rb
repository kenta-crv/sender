if defined?(Sidekiq::Cron)
  Sidekiq::Cron::Job.create(
    name: 'Recording Cleanup - daily at 3am',
    cron: '0 3 * * *',
    class: 'RecordingCleanupJob'
  )

  # サーバーの時刻はJST。cronの数字はそのまま日本時間。
  Sidekiq::Cron::Job.create(
    name: 'SAP Kyujinbox scrape - daily at 2:47',
    cron: '47 2 * * *',
    class: 'KyujinboxScrapeJob'
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP lead resolve and register - Saturday at 3:17',
    cron: '17 3 * * 6',
    class: 'SapLeadResolveJob'
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP sunday url and form detect - Sunday at 3:17',
    cron: '17 3 * * 0',
    class: 'SapSundayFollowUpJob'
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP weekly send - Monday at 9:13',
    cron: '13 9 * * 1',
    class: 'SapWeeklySendJob'
  )
  Sidekiq::Cron::Job.create(
    name: 'SAP weekly report - Friday at 21:43',
    cron: '43 21 * * 5',
    class: 'SapWeeklyReportJob'
  )
end
