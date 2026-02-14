require 'sidekiq'
require 'sidekiq-cron'

redis_url = ENV.fetch('REDIS_URL', 'redis://redis:6379/0')

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
  
  # Configure Sidekiq to listen to queues with the environment-specific prefix
  # In production, ActiveJob uses queue_name_prefix, so we need to match it
  if Rails.env.production?
    queue_prefix = Rails.application.config.active_job.queue_name_prefix
    config.queues = [
      "#{queue_prefix}_default",
      "#{queue_prefix}_mailers"
    ]
  else
    config.queues = [
      "default",
      "mailers"
    ]
  end
  
  # Schedule recurring jobs (only runs in Sidekiq server process)
  # Note: When using active_job: true, don't specify a prefixed queue name -
  # ActiveJob will apply its own prefix automatically
  
  # PayPal Payment Sync - Daily at 6am
  Sidekiq::Cron::Job.create(
    name: 'PayPal Payment Sync - Daily at 6am',
    cron: '0 6 * * *',
    class: 'Paypal::PaymentSyncJob',
    active_job: true
  )
  
  # Recharge Payment Sync - Daily at 6am
  Sidekiq::Cron::Job.create(
    name: 'Recharge Payment Sync - Daily at 6am',
    cron: '0 6 * * *',
    class: 'Recharge::PaymentSyncJob',
    active_job: true
  )

  # Recharge Subscription Sync - Every 6 hours (safety net for missed webhooks)
  Sidekiq::Cron::Job.create(
    name: 'Recharge Subscription Sync - Every 6 hours',
    cron: '0 */6 * * *',
    class: 'Recharge::SubscriptionSyncJob',
    active_job: true
  )

  # Access Controller Ping - Every 10 minutes
  Sidekiq::Cron::Job.create(
    name: 'Access Controller Ping - Every 10 minutes',
    cron: '*/10 * * * *',
    class: 'AccessControllerPingJob',
    active_job: true
  )

  # Access Controller Backup - Daily at 1am
  Sidekiq::Cron::Job.create(
    name: 'Access Controller Backup - Daily at 1am',
    cron: '0 1 * * *',
    class: 'AccessControllerBackupJob',
    active_job: true
  )
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

