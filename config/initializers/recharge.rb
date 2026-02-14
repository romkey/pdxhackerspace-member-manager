Rails.application.config.x.recharge = ActiveSupport::InheritableOptions.new(
  api_key: ENV.fetch('RECHARGE_API_KEY', nil),
  api_base_url: ENV.fetch('RECHARGE_API_BASE_URL', 'https://api.rechargeapps.com'),
  transactions_lookback_days: ENV.fetch('RECHARGE_TRANSACTIONS_LOOKBACK_DAYS', '30').to_i,
  webhook_secret: ENV.fetch('RECHARGE_WEBHOOK_SECRET', nil)
)

module RechargeConfig
  def self.settings
    Rails.application.config.x.recharge
  end

  def self.enabled?
    settings.api_key.present?
  end
end
