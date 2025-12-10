OmniAuth.config.allowed_request_methods = %i[get post]
OmniAuth.config.silence_get_warning = true
OmniAuth.config.logger = Rails.logger

if ENV["APP_BASE_URL"].present?
  OmniAuth.config.full_host = ENV["APP_BASE_URL"]
end

Rails.application.config.middleware.use OmniAuth::Builder do
  next unless AuthentikConfig.enabled_for_login?

  authentik = AuthentikConfig.settings
  callback_url =
    authentik.redirect_uri.presence ||
    File.join(ENV.fetch("APP_BASE_URL", ""), "/auth/authentik/callback").presence ||
    "/auth/authentik/callback"

  provider :openid_connect,
           name: :authentik,
           issuer: authentik.issuer,
           discovery: true,
           scope: %w[openid email profile member_manager_admin],
           response_type: :code,
           pkce: true,
           client_options: {
             identifier: authentik.client_id,
             secret: authentik.client_secret,
             redirect_uri: callback_url
           }
end


