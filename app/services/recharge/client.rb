require 'faraday'

module Recharge
  class Client
    CHARGES_ENDPOINT = '/charges'.freeze

    def initialize(api_key: RechargeConfig.settings.api_key,
                   base_url: RechargeConfig.settings.api_base_url)
      @api_key = api_key
      @base_url = base_url&.delete_suffix('/')
    end

    def charges(start_time: default_start_time, end_time: Time.current)
      raise ArgumentError, 'Recharge API key missing' unless RechargeConfig.enabled?

      start_iso = start_time.utc.iso8601
      end_iso = end_time.utc.iso8601

      results = []
      page = 1
      max_limit = 250 # Recharge API max limit per page (can be up to 250)

      Rails.logger.info("[Recharge::Client] Fetching charges from #{start_iso} to #{end_iso}")

      loop do
        # Use updated_at_min instead of created_at_min to catch charges that were
        # created earlier but processed/updated recently
        params = {
          updated_at_min: start_iso,
          updated_at_max: end_iso,
          limit: max_limit,
          page: page
        }

        Rails.logger.debug { "[Recharge::Client] Fetching page #{page} with limit #{max_limit}" }
        response = connection.get(CHARGES_ENDPOINT, params)
        payload = JSON.parse(response.body)
        charges = Array(payload['charges'])

        Rails.logger.debug { "[Recharge::Client] Page #{page}: received #{charges.size} charges" }

        break if charges.empty?

        results.concat(charges.map { |charge| normalize_charge(charge) })

        Rails.logger.debug { "[Recharge::Client] Total charges collected so far: #{results.size}" }

        # Check if there's a next page
        has_next_page = next_page?(payload, charges.size, max_limit)
        Rails.logger.debug { "[Recharge::Client] Has next page: #{has_next_page}" }

        break unless has_next_page

        page += 1

        # Safety check to prevent infinite loops
        if page > 1000
          Rails.logger.warn('[Recharge::Client] Stopping pagination at page 1000 to prevent infinite loop')
          break
        end
      end

      Rails.logger.info("[Recharge::Client] Finished fetching charges. Total: #{results.size}")
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
        faraday.headers['X-Recharge-Access-Token'] = @api_key
        faraday.headers['Accept'] = 'application/json'
      end
    end

    def next_page?(payload, charges_count, limit)
      meta = payload['meta'] || {}
      next_page = meta['next']

      # Log pagination metadata for debugging
      Rails.logger.debug { "[Recharge::Client] Pagination meta: #{meta.inspect}" }
      Rails.logger.debug { "[Recharge::Client] Charges in this page: #{charges_count}, Limit: #{limit}" }

      # If we got a full page of results, there might be more pages
      # Even if next_page isn't explicitly set, if we got exactly the limit, try the next page
      return true if next_page.present?

      # If we got a full page (equal to limit), assume there might be more pages
      # This handles cases where the API doesn't set the next field but there are more results
      if charges_count >= limit
        Rails.logger.debug { "[Recharge::Client] Got full page (#{charges_count} >= #{limit}), assuming more pages available" }
        return true
      end

      # If we got fewer than the limit, we're definitely on the last page
      false
    end

    def normalize_charge(charge)
      customer = charge['customer'] || {}
      billing = charge['billing_address'] || {}
      name = customer['first_name'].to_s.presence || billing['first_name']
      last = customer['last_name'].to_s.presence || billing['last_name']
      full_name = [name, last].compact_blank.join(' ')

      # Redact billing_address and shipping_address in raw_attributes
      redacted_charge = charge.deep_dup
      redacted_charge['billing_address'] = 'REDACTED' if redacted_charge.key?('billing_address')
      redacted_charge['shipping_address'] = 'REDACTED' if redacted_charge.key?('shipping_address')

      {
        recharge_id: charge['id'].to_s,
        status: charge['status'],
        amount: charge.dig('amount', 'amount') || charge['total_price'],
        currency: charge.dig('amount', 'currency') || charge['currency'],
        processed_at: parse_time(charge['processed_at']) || parse_time(charge['created_at']),
        charge_type: charge['type'],
        customer_id: (customer['id'] || charge['customer_id']).to_s,
        customer_email: customer['email'] || charge['email'],
        customer_name: full_name.presence || customer['billing_first_name'],
        raw_attributes: redacted_charge
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
