require "faraday"

module Recharge
  class Client
    CHARGES_ENDPOINT = "/charges".freeze

    def initialize(api_key: RechargeConfig.settings.api_key,
                   base_url: RechargeConfig.settings.api_base_url)
      @api_key = api_key
      @base_url = base_url&.delete_suffix("/")
    end

    def charges(start_time: default_start_time, end_time: Time.current)
      raise ArgumentError, "Recharge API key missing" unless RechargeConfig.enabled?

      start_iso = start_time.utc.iso8601
      end_iso = end_time.utc.iso8601

      results = []
      page = 1

      loop do
        params = {
          created_at_min: start_iso,
          created_at_max: end_iso,
          limit: 250,
          page: page
        }

        response = connection.get(CHARGES_ENDPOINT, params)
        payload = JSON.parse(response.body)
        charges = Array(payload["charges"])
        break if charges.empty?

        results.concat(charges.map { |charge| normalize_charge(charge) })

        break unless next_page?(payload)

        page += 1
      end

      results
    end

    private

    def default_start_time
      days = RechargeConfig.settings.transactions_lookback_days
      days = 30 if days <= 0
      Time.current - days.days
    end

    def connection
      @connection ||= Faraday.new(url: @base_url) do |faraday|
        faraday.request :url_encoded
        faraday.response :raise_error
        faraday.adapter Faraday.default_adapter
        faraday.headers["X-Recharge-Access-Token"] = @api_key
        faraday.headers["Accept"] = "application/json"
      end
    end

    def next_page?(payload)
      meta = payload["meta"] || {}
      next_page = meta["next"]
      next_page.present?
    end

    def normalize_charge(charge)
      customer = charge["customer"] || {}
      billing = charge["billing_address"] || {}
      name = customer["first_name"].to_s.presence || billing["first_name"]
      last = customer["last_name"].to_s.presence || billing["last_name"]
      full_name = [name, last].compact_blank.join(" ")

      {
        recharge_id: charge["id"].to_s,
        status: charge["status"],
        amount: charge.dig("amount", "amount") || charge["total_price"],
        currency: charge.dig("amount", "currency") || charge["currency"],
        processed_at: parse_time(charge["processed_at"]) || parse_time(charge["created_at"]),
        charge_type: charge["type"],
        customer_email: customer["email"] || charge["email"],
        customer_name: full_name.presence || customer["billing_first_name"],
        raw_attributes: charge
      }
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value)
    rescue ArgumentError
      nil
    end
  end
end

