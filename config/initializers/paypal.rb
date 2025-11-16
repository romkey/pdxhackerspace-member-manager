Rails.application.config.x.paypal = ActiveSupport::InheritableOptions.new(
  client_id: ENV["PAYPAL_CLIENT_ID"],
  client_secret: ENV["PAYPAL_CLIENT_SECRET"],
  api_base_url: ENV.fetch("PAYPAL_API_BASE_URL", "https://api-m.paypal.com"),
  transactions_lookback_days: ENV.fetch("PAYPAL_TRANSACTIONS_LOOKBACK_DAYS", "30").to_i
)

module PaypalConfig
  def self.settings
    Rails.application.config.x.paypal
  end

  def self.enabled?
    settings.client_id.present? && settings.client_secret.present?
  end
end

