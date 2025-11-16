Rails.application.config.x.slack = ActiveSupport::InheritableOptions.new(
  api_token: ENV["SLACK_API_TOKEN"],
  base_url: ENV.fetch("SLACK_API_BASE_URL", "https://slack.com")
)

module SlackConfig
  def self.settings
    Rails.application.config.x.slack
  end

  def self.configured?
    settings.api_token.present?
  end
end

