# SPDX-FileCopyrightText: 2025 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

require 'ipaddr'

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  # Ko-Fi webhook endpoint
  # Ko-Fi sends POST requests with form data containing a "data" field which is a JSON string
  # See: https://help.ko-fi.com/hc/en-us/articles/360004162298-Does-Ko-fi-have-an-API-or-webhook
  def kofi
    # Verify the webhook token if configured
    verification_token = ENV['KOFI_VERIFICATION_TOKEN']

    # Parse the incoming data (Ko-Fi sends it as a form field named 'data')
    begin
      raw_data = params[:data]
      if raw_data.blank?
        Rails.logger.warn("Ko-Fi webhook received with no data")
        head :bad_request
        return
      end

      # Parse the JSON data
      data = JSON.parse(raw_data)

      # Verify the token if one is configured
      if verification_token.present? && data['verification_token'] != verification_token
        Rails.logger.warn("Ko-Fi webhook verification token mismatch")
        head :unauthorized
        return
      end

      # Extract payment details from the webhook
      transaction_id = data['kofi_transaction_id']

      if transaction_id.blank?
        Rails.logger.warn("Ko-Fi webhook missing transaction ID: #{data.inspect}")
        head :bad_request
        return
      end

      # Find or create the payment record
      payment = KofiPayment.find_or_initialize_by(kofi_transaction_id: transaction_id)

      # Update payment attributes
      payment.message_id = data['message_id']
      payment.status = 'completed'
      payment.amount = BigDecimal(data['amount'].to_s) if data['amount'].present?
      payment.currency = data['currency'] || 'USD'
      payment.timestamp = Time.parse(data['timestamp']) if data['timestamp'].present?
      payment.payment_type = data['type']
      payment.from_name = data['from_name']
      payment.email = data['email']
      payment.message = data['message']
      payment.url = data['url']
      payment.is_public = data['is_public'] == true
      payment.is_subscription_payment = data['is_subscription_payment'] == true
      payment.is_first_subscription_payment = data['is_first_subscription_payment'] == true
      payment.tier_name = data['tier_name']
      payment.shop_items = data['shop_items'] || []
      payment.raw_attributes = data
      payment.last_synced_at = Time.current

      # Try to find a matching user by email
      if payment.email.present?
        user = User.find_by('LOWER(email) = ? OR ? = ANY(LOWER(extra_emails::text)::text[])',
                            payment.email.downcase, payment.email.downcase)
        payment.user = user if user
      end

      payment.save!

      Rails.logger.info("Ko-Fi webhook processed: #{transaction_id} - #{payment.payment_type} - #{payment.amount_with_currency} from #{payment.from_name}")

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error("Ko-Fi webhook JSON parse error: #{e.message}")
      head :bad_request
    rescue => e
      Rails.logger.error("Ko-Fi webhook error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      head :internal_server_error
    end
  end

  # Access control webhook endpoint
  # Receives access log lines in the same format as the log files
  # POST /webhooks/access
  # Parameters:
  #   - line: The log line to process (required)
  #   - key: API key for authentication (optional, uses ACCESS_WEBHOOK_KEY env var)
  def access
    # Verify API key if configured
    api_key = ENV['ACCESS_WEBHOOK_KEY']
    if api_key.present?
      provided_key = params[:key] || request.headers['X-Access-Key']
      unless ActiveSupport::SecurityUtils.secure_compare(provided_key.to_s, api_key)
        Rails.logger.warn("Access webhook: invalid API key from #{client_ip}")
        head :unauthorized
        return
      end
    end

    # Get the log line
    line = params[:line]
    if line.blank?
      render json: { error: 'line parameter is required' }, status: :bad_request
      return
    end

    begin
      parser = AccessLogParser.new(line)

      # Skip system messages
      if parser.should_skip?
        Rails.logger.debug("Access webhook: skipping system message: #{line.truncate(100)}")
        render json: { status: 'skipped', reason: 'system message' }, status: :ok
        return
      end

      # Parse and create the access log
      access_log = parser.create_access_log!

      Rails.logger.info("Access webhook: created log entry - #{access_log.name || 'unknown'} #{access_log.action} #{access_log.location}")

      render json: {
        status: 'created',
        id: access_log.id,
        name: access_log.name,
        action: access_log.action,
        location: access_log.location,
        user_id: access_log.user_id,
        logged_at: access_log.logged_at&.iso8601
      }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("Access webhook: validation error: #{e.message}")
      render json: { error: e.message }, status: :unprocessable_entity
    rescue => e
      Rails.logger.error("Access webhook error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      render json: { error: 'Internal error' }, status: :internal_server_error
    end
  end

  def rfid
    unless ip_whitelisted?
      Rails.logger.warn("Webhook request from non-whitelisted IP: #{client_ip}")
      head :forbidden
      return
    end

    # Validate reader key
    reader_key = params[:key] || params[:reader_key]
    if reader_key.blank?
      render json: { error: 'key is required' }, status: :bad_request
      return
    end

    reader = RfidReader.find_by(key: reader_key.to_s.strip)
    unless reader
      Rails.logger.warn("Webhook request with invalid reader key: #{reader_key}")
      render json: { error: 'invalid key' }, status: :unauthorized
      return
    end

    rfid_code = params[:rfid] || params[:rfid_code]
    pin_code = params[:pin] || params[:pin_code] || params[:code]

    if rfid_code.blank? || pin_code.blank?
      render json: { error: 'rfid and pin are required' }, status: :bad_request
      return
    end

    # Validate pin is 4 digits
    unless pin_code.to_s.match?(/\A\d{4}\z/)
      render json: { error: 'pin must be 4 digits' }, status: :bad_request
      return
    end

    RfidWebhookService.store(rfid_code.to_s.strip, pin_code.to_s.strip, reader.id, reader.name)
    Rails.logger.info("RFID webhook received from #{reader.name}: RFID=#{rfid_code}, PIN=#{pin_code[0..1]}**")

    head :ok
  end

  private

  def ip_whitelisted?
    whitelist = ENV['RFID_WEBHOOK_IP_WHITELIST']
    return false if whitelist.blank?

    client_ip_address = client_ip
    return false if client_ip_address.blank?

    whitelist.split(',').map(&:strip).any? do |range|
      ip_in_range?(client_ip_address, range)
    end
  end

  def client_ip
    # Check X-Forwarded-For first (reverse proxy)
    forwarded_for = request.headers['X-Forwarded-For']
    if forwarded_for.present?
      # X-Forwarded-For can contain multiple IPs, take the first one
      return forwarded_for.split(',').first.strip
    end

    # Check X-Real-IP (another common reverse proxy header)
    real_ip = request.headers['X-Real-IP']
    return real_ip.strip if real_ip.present?

    # Fall back to remote_ip
    request.remote_ip
  end

  def ip_in_range?(ip, range)
    # Handle CIDR notation (e.g., "192.168.1.0/24")
    if range.include?('/')
      ipaddr = IPAddr.new(range)
      ipaddr.include?(IPAddr.new(ip))
    # Handle single IP
    elsif range.match?(/\A\d+\.\d+\.\d+\.\d+\z/)
      ip == range
    else
      false
    end
  rescue IPAddr::InvalidAddressError, ArgumentError
    false
  end
end

