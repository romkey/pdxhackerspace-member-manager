require "faraday"

module Paypal
  class Client
    TRANSACTIONS_ENDPOINT = "/v1/reporting/transactions".freeze

    def initialize(client_id: PaypalConfig.settings.client_id,
                   client_secret: PaypalConfig.settings.client_secret,
                   base_url: PaypalConfig.settings.api_base_url)
      @client_id = client_id
      @client_secret = client_secret
      @base_url = base_url&.delete_suffix("/")
    end

    def transactions(start_time: default_start_time, end_time: Time.current)
      raise ArgumentError, "PayPal credentials missing" unless PaypalConfig.enabled?

      start_iso = start_time.utc.iso8601
      end_iso = end_time.utc.iso8601

      results = []
      next_page_token = nil

      loop do
        params = {
          start_date: start_iso,
          end_date: end_iso,
          fields: "all",
          page_size: 500
        }
        params[:page_token] = next_page_token if next_page_token.present?

        response = api_connection.get(TRANSACTIONS_ENDPOINT, params) do |req|
          req.headers["Authorization"] = "Bearer #{access_token}"
          req.headers["Accept"] = "application/json"
        end
        payload = JSON.parse(response.body)
        results.concat(extract_transactions(payload))

        next_page_token = payload["next_page_token"]
        break if next_page_token.blank?
      end

      results
    end

    private

    def default_start_time
      days = PaypalConfig.settings.transactions_lookback_days
      days = 30 if days <= 0
      Time.current - days.days
    end

    def api_connection
      Faraday.new(url: @base_url) do |faraday|
        faraday.response :raise_error
        faraday.adapter Faraday.default_adapter
      end
    end

    def oauth_connection
      @oauth_connection ||= Faraday.new(url: @base_url) do |faraday|
        faraday.request :url_encoded
        faraday.response :raise_error
        faraday.adapter Faraday.default_adapter
      end
    end

    def access_token
      if defined?(@access_token) && @access_token.present? && @access_token_expires_at.present? && Time.current < @access_token_expires_at
        return @access_token
      end

      response = oauth_connection.post("/v1/oauth2/token") do |req|
        req.headers["Authorization"] = "Basic #{encoded_credentials}"
        req.headers["Content-Type"] = "application/x-www-form-urlencoded"
        req.body = { grant_type: "client_credentials" }
      end

      payload = JSON.parse(response.body)
      @access_token = payload["access_token"]
      expires_in = payload["expires_in"].to_i
      @access_token_expires_at = Time.current + [expires_in - 60, 30].max
      @access_token
    end

    def encoded_credentials
      Base64.strict_encode64("#{@client_id}:#{@client_secret}")
    end

    def extract_transactions(payload)
      Array(payload.dig("transaction_details")).map do |entry|
        detail = entry["transaction_info"] || {}
        payer = entry["payer_info"] || {}

        {
          paypal_id: detail["transaction_id"],
          status: detail["transaction_status"],
          amount: detail.dig("transaction_amount", "value"),
          currency: detail.dig("transaction_amount", "currency_code"),
          transaction_time: parse_time(detail["transaction_initiation_date"]),
          transaction_type: detail["transaction_event_code"],
          payer_email: payer["email_address"],
          payer_name: payer["payer_name"] && payer["payer_name"]["alternative_full_name"],
          payer_id: payer["account_id"],
          raw_attributes: entry
        }
      end
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value)
    rescue ArgumentError
      nil
    end
  end
end

