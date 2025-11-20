require 'uri'
require 'faraday/follow_redirects'

module Authentik
  class Client
    DEFAULT_PAGE_SIZE = 200

    API_PREFIX = '/api/v3'.freeze

    def initialize(base_url: AuthentikConfig.settings.api_base_url, token: AuthentikConfig.settings.api_token)
      @base_url = base_url&.delete_suffix('/')
      @token = token
    end

    def group_members(group_id = AuthentikConfig.settings.group_id)
      raise ArgumentError, 'Authentik API token is missing' if @token.blank?
      raise ArgumentError, 'Authentik group ID is missing' if group_id.blank?
      raise ArgumentError, 'Authentik API base URL is missing' if @base_url.blank?

      members = []
      page_size = AuthentikConfig.settings.group_page_size.to_i
      page_size = DEFAULT_PAGE_SIZE if page_size <= 0

      base_params = { groups_by_pk: group_id, page_size: page_size }
      next_path = build_user_path(base_params)

      total_count = nil

      while next_path.present?
        log_request(next_path)
        response = connection.get(next_path)
        handle_error!(response)

        payload = JSON.parse(response.body)
        log_page_metadata(payload)
        total_count ||= payload['count']
        members.concat(extract_members(payload))
        next_path = next_page_path(payload, base_params)
      end

      members
    end

    private

    def connection
      @connection ||= Faraday.new(url: @base_url) do |faraday|
        faraday.request :authorization, 'Bearer', @token
        faraday.response :follow_redirects
        faraday.response :raise_error
        faraday.adapter Faraday.default_adapter
      end
    end

    def handle_error!(response)
      return if response.success?

      raise StandardError, "Authentik API error (#{response.status}): #{response.body}"
    end

    def extract_members(payload)
      results = payload['results'] || payload
      results.map { |entry| normalize_member(entry) }.compact
    end

    def build_user_path(params)
      query = URI.encode_www_form(params)
      "#{API_PREFIX}/core/users/?#{query}"
    end

    def next_page_path(payload, base_params)
      next_link = payload['next'].presence || (payload['pagination'] || {})['next']
      return if next_link.blank?

      if next_link.is_a?(String)
        return URI(next_link).request_uri if next_link.start_with?('http')

        return next_link
      end

      if next_link.is_a?(Integer)
        return if next_link <= 0

        return build_user_path(base_params.merge(page: next_link))
      end

      nil
    end

    def normalize_member(entry)
      user_data = entry['user'] || entry

      {
        authentik_id: (user_data['pk'] || user_data['id'] || entry['pk'] || entry['id']).to_s,
        email: normalize_email(user_data['email']),
        full_name: user_data['name'] || [user_data['first_name'], user_data['last_name']].compact_blank.join(' '),
        active: !entry['is_active'].in?([false, 'false']),
        attributes: extract_attributes(entry, user_data)
      }
    rescue NoMethodError
      nil
    end

    def log_page_metadata(payload)
      return unless payload.is_a?(Hash)

      metadata = payload.dup
      metadata.delete('results')
      metadata.delete('objects')

      Rails.logger.info("Authentik page metadata: #{metadata.to_json}")
    end

    def log_request(path)
      Rails.logger.info("Authentik request: #{File.join(@base_url, path)}")
    end

    def normalize_email(value)
      value.to_s.strip.presence
    end

    def extract_attributes(entry, user_data)
      attrs = entry['attributes'] || user_data['attributes']
      return {} unless attrs.is_a?(Hash)

      attrs
    end
  end
end
