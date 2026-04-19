Rails.application.config.x.slack = ActiveSupport::InheritableOptions.new(
  api_token: ENV["SLACK_API_TOKEN"],
  base_url: ENV.fetch("SLACK_API_BASE_URL", "https://slack.com")
)

# Sign in with Slack (OpenID Connect) — used only to link a workspace Slack user id to a member
# after they are already logged in via Authentik. Not used for Member Manager login.
Rails.application.config.x.slack_oidc = ActiveSupport::InheritableOptions.new(
  client_id: ENV["SLACK_OIDC_CLIENT_ID"],
  client_secret: ENV["SLACK_OIDC_CLIENT_SECRET"],
  team_id: ENV["SLACK_TEAM_ID"]
)

module SlackConfig
  def self.settings
    Rails.application.config.x.slack
  end

  def self.configured?
    settings.api_token.present?
  end
end

module SlackOidcConfig
  def self.settings
    Rails.application.config.x.slack_oidc
  end

  def self.configured?
    settings.client_id.present? && settings.client_secret.present? && settings.team_id.present?
  end
end
