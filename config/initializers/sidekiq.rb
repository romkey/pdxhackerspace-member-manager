require 'sidekiq'
require 'sidekiq-cron'

redis_url = ENV.fetch('REDIS_URL', 'redis://redis:6379/0')

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }

  # Plain queue names — no prefix needed since this app has its own Redis instance.
  # Do NOT use ActiveJob queue_name_prefix; it double-prefixes with sidekiq-cron.
  config.queues = %w[default mailers]

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

  # AI / Ollama health - Every 10 minutes
  Sidekiq::Cron::Job.create(
    name: 'AI Ollama Health Check - Every 10 minutes',
    cron: '*/10 * * * *',
    class: 'AiOllamaHealthCheckJob',
    active_job: true
  )

  # Printer health - Every 10 minutes
  Sidekiq::Cron::Job.create(
    name: 'Printer Health Check - Every 10 minutes',
    cron: '*/10 * * * *',
    class: 'PrinterHealthCheckJob',
    active_job: true
  )

  # Access Controller Backup - Daily at 1am
  Sidekiq::Cron::Job.create(
    name: 'Access Controller Backup - Daily at 1am',
    cron: '0 1 * * *',
    class: 'AccessControllerBackupJob',
    active_job: true
  )

  # Parking Notice Expiration - Daily at 7am
  Sidekiq::Cron::Job.create(
    name: 'Parking Notice Expiration - Daily at 7am',
    cron: '0 7 * * *',
    class: 'ParkingNoticeExpirationJob',
    active_job: true
  )

  # Login Link Expiration - Daily at 8am
  Sidekiq::Cron::Job.create(
    name: 'Login Link Expiration - Daily at 8am',
    cron: '0 8 * * *',
    class: 'LoginLinkExpirationJob',
    active_job: true
  )

  # Message Trash Cleanup - Daily at 5am
  Sidekiq::Cron::Job.create(
    name: 'Message Trash Cleanup - Daily at 5am',
    cron: '0 5 * * *',
    class: 'MessageTrashCleanupJob',
    active_job: true
  )
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
