require 'sidekiq'

redis_url = ENV.fetch('REDIS_URL', 'redis://redis:6379/0')

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
  # Configure Sidekiq to listen to queues with the environment-specific prefix
  config.queues = [
    "member_manager_#{Rails.env}_default",
    "member_manager_#{Rails.env}_mailers"
  ]
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end

