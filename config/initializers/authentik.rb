Rails.application.config.x.authentik = ActiveSupport::InheritableOptions.new(
  issuer: ENV.fetch('AUTHENTIK_ISSUER', nil),
  client_id: ENV.fetch('AUTHENTIK_CLIENT_ID', nil),
  client_secret: ENV.fetch('AUTHENTIK_CLIENT_SECRET', nil),
  redirect_uri: ENV.fetch('AUTHENTIK_REDIRECT_URI', nil),
  group_id: ENV.fetch('AUTHENTIK_GROUP_ID', nil),
  api_base_url: ENV['AUTHENTIK_API_BASE_URL'] || ENV.fetch('AUTHENTIK_ISSUER', nil),
  api_token: ENV.fetch('AUTHENTIK_TOKEN', '').strip.presence,
  group_page_size: ENV.fetch('AUTHENTIK_GROUP_PAGE_SIZE', 200).to_i,
  webhook_secret: ENV.fetch('AUTHENTIK_WEBHOOK_SECRET', nil)
)

module AuthentikConfig
  def self.settings
    Rails.application.config.x.authentik
  end

  def self.enabled_for_login?
    settings.client_id.present? && settings.client_secret.present? && settings.issuer.present?
  end

  # Bearer REST API calls require token + base URL (see +Authentik::Client#validate_api_config!+).
  def self.api_ready?
    settings.api_token.present? && settings.api_base_url.present?
  end
end

# API token may be unset during local bootstrap; Authentik REST features stay disabled until configured.
# The admin dashboard surfaces this in the Urgent section.
unless Rails.env.test? || ENV['SECRET_KEY_BASE_DUMMY'].present?
  token = ENV.fetch('AUTHENTIK_TOKEN', '').strip
  if token.blank?
    msg = 'MemberManager: AUTHENTIK_TOKEN is missing or empty. OIDC login may still work; set a ' \
          'service account API token for group sync, provisioning, and webhooks.'
    Rails.logger.warn(msg)
    warn(msg)
  end
end
