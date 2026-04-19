# frozen_string_literal: true

require 'jwt'

module Slack
  # Sign in with Slack (OpenID Connect) — token exchange and id_token decode.
  # Used only after the member is logged in via Authentik; not for MM login.
  class OpenidConnect
    AUTHORIZE_PATH = '/openid/connect/authorize'
    TOKEN_PATH = '/api/openid.connect.token'
    SCOPES = 'openid email profile'

    class << self
      def authorization_uri(state:, nonce:, redirect_uri:, team_id:)
        raise ArgumentError, 'state is required' if state.blank?
        raise ArgumentError, 'nonce is required' if nonce.blank?
        raise ArgumentError, 'redirect_uri is required' if redirect_uri.blank?

        client_id = SlackOidcConfig.settings.client_id
        raise ArgumentError, 'Slack OIDC client_id is missing' if client_id.blank?

        base = SlackConfig.settings.base_url.to_s.chomp('/')
        params = {
          response_type: 'code',
          scope: SCOPES,
          client_id: client_id,
          redirect_uri: redirect_uri,
          state: state,
          nonce: nonce
        }
        params[:team] = team_id if team_id.present?

        uri = URI.parse("#{base}#{AUTHORIZE_PATH}")
        uri.query = URI.encode_www_form(params)
        uri.to_s
      end

      def exchange_code(code:, redirect_uri:)
        raise ArgumentError, 'code is required' if code.blank?

        client_id = SlackOidcConfig.settings.client_id
        client_secret = SlackOidcConfig.settings.client_secret
        raise ArgumentError, 'Slack OIDC is not configured' if client_id.blank? || client_secret.blank?

        base = SlackConfig.settings.base_url.to_s.chomp('/')
        conn = Faraday.new(url: base) do |f|
          f.request :url_encoded
          f.adapter Faraday.default_adapter
        end

        response = conn.post(TOKEN_PATH) do |req|
          req.body = {
            grant_type: 'authorization_code',
            code: code,
            client_id: client_id,
            client_secret: client_secret,
            redirect_uri: redirect_uri
          }
        end

        # Slack returns HTTP 200 with ok: false for OAuth errors.
        JSON.parse(response.body)
      end

      # Decodes the id_token from Slack (RS256). We trust this token only when it was
      # returned by +exchange_code+ over HTTPS with our client_secret.
      def decode_id_token!(id_token)
        raise ArgumentError, 'id_token is required' if id_token.blank?

        payload, = JWT.decode(id_token, nil, false)
        payload.stringify_keys
      end
    end
  end
end
