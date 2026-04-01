module Authentik
  # Reads the static Authentik API Bearer token from +AUTHENTIK_TOKEN+ (see +AuthentikConfig+).
  # OAuth2 client-credentials / refresh flows are not used for API access.
  module TokenManager
    class << self
      def token
        AuthentikConfig.settings.api_token.to_s.strip.presence
      end
    end
  end
end
