module Authentik
  # Manages Authentik API tokens with automatic OAuth2 client credentials refresh.
  #
  # When AUTHENTIK_CLIENT_ID, AUTHENTIK_CLIENT_SECRET, and AUTHENTIK_ISSUER are
  # configured, this class uses the OAuth2 client credentials grant with the
  # `goauthentik.io/api` scope to obtain a JWT token that can authenticate to
  # the Authentik API. The token is cached and automatically refreshed before
  # it expires.
  #
  # Falls back to the static AUTHENTIK_API_TOKEN environment variable if OAuth
  # credentials are not configured or if the token request fails.
  #
  # IMPORTANT: The service account created by the client credentials flow
  # (named `ak-<provider>-client-credentials` in Authentik) must have
  # sufficient permissions (e.g., be added to an admin group) in Authentik
  # for API operations to succeed.
  class TokenManager
    CACHE_KEY = 'authentik:api_jwt_token'.freeze
    DISCOVERY_CACHE_KEY = 'authentik:oidc_discovery'.freeze
    API_SCOPE = 'goauthentik.io/api'.freeze

    # Refresh the token 120 seconds before it actually expires to avoid
    # race conditions where a token expires mid-request.
    EXPIRY_BUFFER_SECONDS = 120

    class << self
      # Returns a valid API token, using OAuth client credentials if configured,
      # otherwise falling back to the static AUTHENTIK_API_TOKEN.
      def token
        if oauth_configured?
          fetch_or_refresh_oauth_token
        else
          static_token
        end
      end

      # Whether OAuth-based token management is available
      def oauth_configured?
        settings.client_id.present? &&
          settings.client_secret.present? &&
          settings.issuer.present?
      end

      # Force-clear the cached token (useful after a 401/403 response)
      def clear_cached_token!
        Rails.cache.delete(CACHE_KEY)
        Rails.logger.info('[Authentik::TokenManager] Cached token cleared')
      end

      # Returns diagnostic info about the current token state
      def status
        {
          oauth_configured: oauth_configured?,
          static_token_present: settings.api_token.present?,
          cached_token_present: Rails.cache.read(CACHE_KEY).present?,
          token_endpoint: discover_token_endpoint
        }
      end

      private

      def fetch_or_refresh_oauth_token
        # Return cached token if still valid
        cached = Rails.cache.read(CACHE_KEY)
        return cached if cached.present?

        # Fetch a new token via OAuth2 client credentials
        jwt = request_oauth_token
        if jwt.present?
          jwt
        else
          Rails.logger.warn('[Authentik::TokenManager] OAuth token unavailable, falling back to static token')
          static_token
        end
      rescue StandardError => e
        Rails.logger.error("[Authentik::TokenManager] OAuth token fetch failed: #{e.class}: #{e.message}")
        static_token
      end

      def request_oauth_token
        token_endpoint = discover_token_endpoint
        if token_endpoint.blank?
          Rails.logger.error('[Authentik::TokenManager] Could not determine token endpoint')
          return nil
        end

        Rails.logger.info("[Authentik::TokenManager] Requesting OAuth token from #{token_endpoint}")

        response = Faraday.post(token_endpoint) do |req|
          req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          req.body = URI.encode_www_form(
            grant_type: 'client_credentials',
            client_id: settings.client_id,
            client_secret: settings.client_secret,
            scope: API_SCOPE
          )
        end

        unless response.success?
          Rails.logger.error(
            "[Authentik::TokenManager] Token request failed (#{response.status}): #{response.body.to_s.truncate(500)}"
          )
          return nil
        end

        payload = JSON.parse(response.body)
        access_token = payload['access_token']
        expires_in = payload['expires_in'].to_i

        if access_token.blank?
          Rails.logger.error('[Authentik::TokenManager] Token response missing access_token')
          return nil
        end

        # Cache with a buffer before expiry
        cache_ttl = [expires_in - EXPIRY_BUFFER_SECONDS, 30].max
        Rails.cache.write(CACHE_KEY, access_token, expires_in: cache_ttl)

        Rails.logger.info(
          "[Authentik::TokenManager] Obtained OAuth JWT token (expires in #{expires_in}s, cached for #{cache_ttl}s)"
        )

        access_token
      rescue JSON::ParserError => e
        Rails.logger.error("[Authentik::TokenManager] Failed to parse token response: #{e.message}")
        nil
      end

      def discover_token_endpoint
        # Use explicit config if set
        explicit = settings.token_endpoint
        if explicit.present?
          validated = validate_token_endpoint_against_issuer(explicit)
          return validated if validated.present?

          Rails.logger.error(
            '[Authentik::TokenManager] AUTHENTIK_TOKEN_ENDPOINT host/port does not match AUTHENTIK_ISSUER; refusing.'
          )
          return nil
        end

        # Try OIDC discovery, with caching
        cached_endpoint = Rails.cache.read(DISCOVERY_CACHE_KEY)
        if cached_endpoint.present?
          validated = validate_token_endpoint_against_issuer(cached_endpoint)
          return validated if validated.present?

          Rails.cache.delete(DISCOVERY_CACHE_KEY)
        end

        issuer = settings.issuer
        return nil if issuer.blank?

        discovery_url = "#{issuer.delete_suffix('/')}/.well-known/openid-configuration"
        Rails.logger.info("[Authentik::TokenManager] Discovering token endpoint from #{discovery_url}")

        response = Faraday.get(discovery_url)
        unless response.success?
          Rails.logger.error(
            "[Authentik::TokenManager] OIDC discovery failed (#{response.status}): #{response.body.to_s.truncate(200)}"
          )
          return nil
        end

        endpoint = JSON.parse(response.body)['token_endpoint']
        if endpoint.present?
          validated = validate_token_endpoint_against_issuer(endpoint)
          if validated.blank?
            Rails.logger.error(
              '[Authentik::TokenManager] Discovered token_endpoint host/port does not match issuer; rejecting.'
            )
            return nil
          end

          endpoint = validated
          # Cache discovery result for 24 hours — it rarely changes
          Rails.cache.write(DISCOVERY_CACHE_KEY, endpoint, expires_in: 24.hours)
          Rails.logger.info("[Authentik::TokenManager] Discovered token endpoint: #{endpoint}")
        end

        endpoint
      rescue URI::InvalidURIError => e
        Rails.logger.error("[Authentik::TokenManager] Invalid URI in OIDC discovery: #{e.message}")
        nil
      rescue StandardError => e
        Rails.logger.error("[Authentik::TokenManager] OIDC discovery error: #{e.class}: #{e.message}")
        nil
      end

      def static_token
        settings.api_token
      end

      def validate_token_endpoint_against_issuer(endpoint)
        return nil if endpoint.blank?

        issuer = settings.issuer.to_s.delete_suffix('/')
        return endpoint if issuer.blank?

        endpoint_uri = URI.parse(endpoint)
        issuer_uri = URI.parse(issuer)
        return endpoint if endpoint_uri.host == issuer_uri.host && endpoint_uri.port == issuer_uri.port

        nil
      rescue URI::InvalidURIError => e
        Rails.logger.error("[Authentik::TokenManager] Invalid token endpoint URI: #{e.message}")
        nil
      end

      def settings
        AuthentikConfig.settings
      end
    end
  end
end
