require 'faraday'

module Paypal
  class Client
    TRANSACTIONS_ENDPOINT = '/v1/reporting/transactions'.freeze

    def initialize(client_id: PaypalConfig.settings.client_id,
                   client_secret: PaypalConfig.settings.client_secret,
                   base_url: PaypalConfig.settings.api_base_url)
      @client_id = client_id
      @client_secret = client_secret
      @base_url = base_url&.delete_suffix('/')
    end

    def transactions(start_time: default_start_time, end_time: Time.current)
      raise ArgumentError, 'PayPal credentials missing' unless PaypalConfig.enabled?

      results = []
      max_days_per_request = 31

      # Capture end_time once to avoid Time.current changing between calls
      final_end = end_time
      current_start = start_time

      # Validate overall date range
      if current_start >= final_end
        Rails.logger.warn("[PayPal::Client] Invalid date range: start_time (#{current_start.utc.iso8601}) >= end_time (#{final_end.utc.iso8601})")
        return []
      end

      Rails.logger.info("[PayPal::Client] Fetching transactions from #{current_start.utc.iso8601} to #{final_end.utc.iso8601}")
      Rails.logger.info('[PayPal::Client] PayPal API limit: 31 days per request, will fetch in chunks')

      # Fetch data in 31-day chunks
      loop do
        # Break if we've reached or passed the end
        break if current_start >= final_end

        # Calculate the end date for this chunk (31 days from start, or final_end, whichever is earlier)
        potential_end = current_start + max_days_per_request.days
        chunk_end = [potential_end, final_end].min

        # Ensure chunk_end is strictly greater than current_start with at least 1 second difference
        # PayPal requires start_date < end_date (not <=) and may reject identical timestamps
        time_diff = chunk_end - current_start
        if chunk_end <= current_start || time_diff < 1
          Rails.logger.warn("[PayPal::Client] Skipping chunk with invalid date range: #{current_start.utc.iso8601} to #{chunk_end.utc.iso8601}, diff: #{time_diff}s")
          break
        end

        Rails.logger.info("[PayPal::Client] Fetching chunk: #{current_start.utc.iso8601} to #{chunk_end.utc.iso8601}")

        # Fetch all pages for this date range
        chunk_results = fetch_transactions_for_date_range(current_start, chunk_end)
        results.concat(chunk_results)

        Rails.logger.info("[PayPal::Client] Chunk complete: #{chunk_results.size} transactions")

        # Move to the next chunk (start from the end of this chunk)
        # If we've reached or passed the final_end, we're done
        if chunk_end >= final_end
          Rails.logger.debug('[PayPal::Client] Reached final_end, stopping chunking')
          break
        end

        # Set next start to current chunk_end
        current_start = chunk_end

        # Final safety check: if current_start is now at or past final_end, we're done
        if current_start >= final_end
          Rails.logger.debug { "[PayPal::Client] current_start (#{current_start.utc.iso8601}) >= final_end (#{final_end.utc.iso8601}), stopping" }
          break
        end
      end

      Rails.logger.info("[PayPal::Client] Finished fetching all transactions. Total: #{results.size}")
      results
    end

    def fetch_transactions_for_date_range(start_time, end_time)
      # Validate date range - PayPal requires start_date < end_date
      # Also ensure there's at least 1 second difference (PayPal may reject identical timestamps)
      time_diff = end_time - start_time
      if start_time >= end_time || time_diff < 1
        Rails.logger.warn("[PayPal::Client] Skipping invalid date range: start_time (#{start_time.utc.iso8601}) >= end_time (#{end_time.utc.iso8601}), diff: #{time_diff}s")
        return []
      end

      start_iso = start_time.utc.iso8601
      end_iso = end_time.utc.iso8601

      # Double-check the ISO strings aren't identical (defensive check)
      if start_iso == end_iso
        Rails.logger.warn("[PayPal::Client] Skipping request with identical ISO timestamps: #{start_iso}")
        return []
      end

      results = []
      next_page_token = nil
      page = 1

      loop do
        params = {
          start_date: start_iso,
          end_date: end_iso,
          fields: 'all',
          page_size: 500,
          transaction_class: 'Received' # Only fetch received payments, not sent payments
        }
        params[:page_token] = next_page_token if next_page_token.present?

        Rails.logger.debug { "[PayPal::Client] Fetching page #{page} for date range #{start_iso} to #{end_iso}" }
        Rails.logger.debug { "[PayPal::Client] Request params: #{params.inspect}" }

        response = api_connection.get(TRANSACTIONS_ENDPOINT, params) do |req|
          req.headers['Authorization'] = "Bearer #{access_token}"
          req.headers['Accept'] = 'application/json'
          req.headers['Content-Type'] = 'application/json'
        end

        Rails.logger.debug { "[PayPal::Client] Response status: #{response.status}" }

        payload = JSON.parse(response.body)
        Rails.logger.debug { "[PayPal::Client] Response body keys: #{payload.keys.inspect}" }

        page_transactions = extract_transactions(payload)
        results.concat(page_transactions)

        Rails.logger.debug { "[PayPal::Client] Page #{page}: received #{page_transactions.size} transactions (total in chunk: #{results.size})" }

        next_page_token = payload['next_page_token']
        break if next_page_token.blank?

        page += 1

        # Safety check to prevent infinite loops
        if page > 1000
          Rails.logger.warn('[PayPal::Client] Stopping pagination at page 1000 to prevent infinite loop')
          break
        end
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
        faraday.response :logger, Rails.logger, bodies: true if Rails.env.development?
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
      Rails.logger.debug('[PayPal::Client] access_token called')

      # Check if we have a valid cached token
      if defined?(@access_token) && @access_token.present? && @access_token_expires_at.present? && Time.current < @access_token_expires_at
        time_until_expiry = @access_token_expires_at - Time.current
        Rails.logger.debug { "[PayPal::Client] Using cached access token (expires in #{time_until_expiry.round} seconds)" }
        Rails.logger.debug { "[PayPal::Client] Token expires at: #{@access_token_expires_at}" }
        return @access_token
      end

      # Need to fetch a new token
      if defined?(@access_token) && @access_token.present?
        if @access_token_expires_at.present?
          Rails.logger.debug { "[PayPal::Client] Cached token expired at #{@access_token_expires_at}, fetching new token" }
        else
          Rails.logger.debug('[PayPal::Client] Cached token missing expiration time, fetching new token')
        end
      else
        Rails.logger.debug('[PayPal::Client] No cached token found, fetching new token')
      end

      Rails.logger.debug('[PayPal::Client] Requesting new access token from /v1/oauth2/token')
      Rails.logger.debug { "[PayPal::Client] Using base URL: #{@base_url}" }

      # Request token - PayPal determines available scopes based on app configuration
      # The scope parameter is optional and may be ignored if the app doesn't have that feature enabled
      token_body = { grant_type: 'client_credentials' }

      # Try requesting the reporting scope, but PayPal will only grant what the app is configured for
      reporting_scope = 'https://uri.paypal.com/services/reporting/search/read'
      token_body[:scope] = reporting_scope
      Rails.logger.debug { "[PayPal::Client] Requesting scope: #{reporting_scope}" }

      response = oauth_connection.post('/v1/oauth2/token') do |req|
        req.headers['Authorization'] = "Basic #{encoded_credentials}"
        req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
        req.body = token_body
      end

      Rails.logger.debug { "[PayPal::Client] Token response status: #{response.status}" }

      payload = JSON.parse(response.body)
      @access_token = payload['access_token']
      expires_in = payload['expires_in'].to_i
      @access_token_expires_at = Time.current + [expires_in - 60, 30].max

      # Log the scopes that were actually granted
      if payload['scope']
        Rails.logger.debug { "[PayPal::Client] Token granted scopes: #{payload['scope']}" }
      else
        Rails.logger.warn('[PayPal::Client] Token response did not include scope information')
      end

      Rails.logger.debug('[PayPal::Client] Successfully fetched new access token')
      Rails.logger.debug { "[PayPal::Client] Token expires in #{expires_in} seconds (from API)" }
      Rails.logger.debug { "[PayPal::Client] Token will be considered expired at: #{@access_token_expires_at} (60 seconds before actual expiry)" }
      Rails.logger.debug { "[PayPal::Client] Token preview: #{@access_token[0..20]}..." }

      @access_token
    end

    def encoded_credentials
      Base64.strict_encode64("#{@client_id}:#{@client_secret}")
    end

    def extract_transactions(payload)
      Array(payload['transaction_details']).map do |entry|
        detail = entry['transaction_info'] || {}
        payer = entry['payer_info'] || {}

        amount_value = detail.dig('transaction_amount', 'value')
        transaction_type = detail['transaction_event_code']
        payer_email = payer['email_address']
        payer_name = payer['payer_name'] && payer['payer_name']['alternative_full_name']

        # Only include received payments (money coming IN to our account)
        # Skip if amount is missing
        if amount_value.nil?
          Rails.logger.debug { "[PayPal::Client] SKIPPING: Missing amount | Email: #{payer_email} | Name: #{payer_name} | Type: #{transaction_type}" }
          next
        end

        # Convert amount to float for comparison
        amount_float = amount_value.to_f

        # Skip if amount is negative or zero (these are expenses/refunds/outgoing payments)
        if amount_float <= 0
          Rails.logger.debug { "[PayPal::Client] SKIPPING: Amount <= 0 (#{amount_value}) | Email: #{payer_email} | Name: #{payer_name} | Type: #{transaction_type}" }
          next
        end

        # Only include transaction types that represent received payments
        # Common received payment types in PayPal:
        # T1107 = Payment received (most common)
        # T0003 = Payment received
        # T0001 = Payment received
        # T1106 = Payment received
        # T1111 = Payment received (subscription)
        # T1117 = Payment received (recurring)
        # T0002 = Withdrawal (money received into account - PayPal calls this "expense" but it's money we received)
        received_payment_types = %w[T1107 T0003 T0001 T1106 T1111 T1117 T0002]

        # Exclude known expense/outgoing transaction types (but NOT T0002 - that's money we received)
        # T0004 = Debit card purchase
        # T0005 = Credit card withdrawal
        # T0006 = Credit card deposit (outgoing)
        # T0007 = Payment sent
        # T0008 = Payment sent
        expense_types = %w[T0004 T0005 T0006 T0007 T0008 T0009 T0010]
        if expense_types.include?(transaction_type)
          Rails.logger.debug { "[PayPal::Client] SKIPPING: Expense type (#{transaction_type}) | Amount: #{amount_value} | Email: #{payer_email} | Name: #{payer_name}" }
          next
        end

        # Safety check: If transaction_class filter didn't work, use whitelist
        # Only include transactions that are in our whitelist of received payment types
        # This ensures we only record money received, not money spent
        unless received_payment_types.include?(transaction_type)
          Rails.logger.debug { "[PayPal::Client] SKIPPING: Not in received payment whitelist (type: #{transaction_type}) | Amount: #{amount_value} | Email: #{payer_email} | Name: #{payer_name}" }
          next
        end

        # Log payments that are being included
        Rails.logger.debug { "[PayPal::Client] INCLUDING: Type: #{transaction_type} | Amount: #{amount_value} | Email: #{payer_email} | Name: #{payer_name}" }

        {
          paypal_id: detail['transaction_id'],
          status: detail['transaction_status'],
          amount: amount_value,
          currency: detail.dig('transaction_amount', 'currency_code'),
          transaction_time: parse_time(detail['transaction_initiation_date']),
          transaction_type: transaction_type,
          payer_email: payer['email_address'],
          payer_name: payer['payer_name'] && payer['payer_name']['alternative_full_name'],
          payer_id: payer['account_id'],
          raw_attributes: entry
        }
      end.compact
    end

    def parse_time(value)
      return if value.blank?

      Time.zone.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
