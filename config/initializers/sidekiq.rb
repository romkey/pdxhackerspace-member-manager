require 'sidekiq'

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
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

