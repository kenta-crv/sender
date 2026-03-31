if defined?(Sidekiq::Cron)
  Sidekiq::Cron::Job.create(
    name: 'Recording Cleanup - daily at 3am',
    cron: '0 3 * * *',
    class: 'RecordingCleanupJob'
  )
end
