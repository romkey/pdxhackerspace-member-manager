Rails.application.config.x.recharge = ActiveSupport::InheritableOptions.new(
  api_key: ENV["RECHARGE_API_KEY"],
  api_base_url: ENV.fetch("RECHARGE_API_BASE_URL", "https://api.rechargeapps.com"),
  transactions_lookback_days: ENV.fetch("RECHARGE_TRANSACTIONS_LOOKBACK_DAYS", "30").to_i
)

module RechargeConfig
  def self.settings
    Rails.application.config.x.recharge
  end

  def self.enabled?
    settings.api_key.present?
  end
end

