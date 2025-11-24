# SPDX-FileCopyrightText: 2025 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

require 'ipaddr'

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :require_authenticated_user!, only: [:rfid]

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

