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
  queue_name = Rails.env.production? ? "#{Rails.application.config.active_job.queue_name_prefix}_default" : 'default'
  
  # PayPal Payment Sync - Daily at 7am
  begin
    paypal_job = Sidekiq::Cron::Job.find('PayPal Payment Sync - Daily at 7am')
    paypal_job.cron = '0 7 * * *'
    paypal_job.class_name = 'Paypal::PaymentSyncJob'
    paypal_job.queue_name = queue_name
    paypal_job.save
  rescue
    Sidekiq::Cron::Job.create(
      name: 'PayPal Payment Sync - Daily at 7am',
      cron: '0 7 * * *', # 7am every day
      class: 'Paypal::PaymentSyncJob',
      queue: queue_name
    )
  end
  
  # Recharge Payment Sync - Daily at 7am
  begin
    recharge_job = Sidekiq::Cron::Job.find('Recharge Payment Sync - Daily at 7am')
    recharge_job.cron = '0 7 * * *'
    recharge_job.class_name = 'Recharge::PaymentSyncJob'
    recharge_job.queue_name = queue_name
    recharge_job.save
  rescue
    Sidekiq::Cron::Job.create(
      name: 'Recharge Payment Sync - Daily at 7am',
      cron: '0 7 * * *', # 7am every day
      class: 'Recharge::PaymentSyncJob',
      queue: queue_name
    )
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

