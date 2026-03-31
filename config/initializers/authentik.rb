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
end

# Service account API token is mandatory at runtime. Skip during tests and when precompiling
# assets in Docker (+SECRET_KEY_BASE_DUMMY+).
unless Rails.env.test? || ENV['SECRET_KEY_BASE_DUMMY'].present?
  token = ENV.fetch('AUTHENTIK_TOKEN', '').strip
  if token.blank?
    msg = 'MemberManager: AUTHENTIK_TOKEN is missing or empty. Set it to your Authentik service ' \
          'account API token. The app will send it as Authorization: Bearer. Refusing to start.'
    Rails.logger.error(msg)
    warn(msg)
    # Boot must not continue without API credentials; abort is intentional (avoid infinite Sidekiq/API failures).
    abort(msg) # rubocop:disable Rails/Exit -- fail fast when Authentik API token is unset
  end
end
