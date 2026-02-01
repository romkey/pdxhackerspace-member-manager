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

    # ========== Notification Transports ==========

    def list_notification_transports(name: nil)
      validate_api_config!
      params = { page_size: DEFAULT_PAGE_SIZE }
      params[:name] = name if name.present?
      get_paginated("#{API_PREFIX}/events/transports/", params)
    end

    def create_notification_transport(name:, mode:, webhook_url:, send_once: true, webhook_mapping: nil)
      validate_api_config!
      body = {
        name: name,
        mode: mode,
        webhook_url: webhook_url,
        send_once: send_once
      }
      body[:webhook_mapping] = webhook_mapping if webhook_mapping.present?

      post_json("#{API_PREFIX}/events/transports/", body)
    end

    def update_notification_transport(transport_id, **attrs)
      validate_api_config!
      patch_json("#{API_PREFIX}/events/transports/#{transport_id}/", attrs)
    end

    def delete_notification_transport(transport_id)
      validate_api_config!
      delete_resource("#{API_PREFIX}/events/transports/#{transport_id}/")
    end

    # ========== Event Matcher Policies ==========

    def list_event_matcher_policies(name: nil)
      validate_api_config!
      params = { page_size: DEFAULT_PAGE_SIZE }
      params[:name] = name if name.present?
      get_paginated("#{API_PREFIX}/policies/event_matcher/", params)
    end

    def create_event_matcher_policy(name:, action: nil, client_ip: nil, app: nil, model: nil)
      validate_api_config!
      body = { name: name }
      body[:action] = action if action.present?
      body[:client_ip] = client_ip if client_ip.present?
      body[:app] = app if app.present?
      body[:model] = model if model.present?

      post_json("#{API_PREFIX}/policies/event_matcher/", body)
    end

    def update_event_matcher_policy(policy_id, **attrs)
      validate_api_config!
      patch_json("#{API_PREFIX}/policies/event_matcher/#{policy_id}/", attrs)
    end

    def delete_event_matcher_policy(policy_id)
      validate_api_config!
      delete_resource("#{API_PREFIX}/policies/event_matcher/#{policy_id}/")
    end

    # ========== Notification Rules ==========

    def list_notification_rules(name: nil)
      validate_api_config!
      params = { page_size: DEFAULT_PAGE_SIZE }
      params[:name] = name if name.present?
      get_paginated("#{API_PREFIX}/events/rules/", params)
    end

    def create_notification_rule(name:, transports:, group:, severity: 'notice')
      validate_api_config!
      body = {
        name: name,
        transports: Array(transports),
        group: group,
        severity: severity
      }

      post_json("#{API_PREFIX}/events/rules/", body)
    end

    def update_notification_rule(rule_id, **attrs)
      validate_api_config!
      patch_json("#{API_PREFIX}/events/rules/#{rule_id}/", attrs)
    end

    def delete_notification_rule(rule_id)
      validate_api_config!
      delete_resource("#{API_PREFIX}/events/rules/#{rule_id}/")
    end

    # ========== Policy Bindings ==========

    def list_policy_bindings(target: nil)
      validate_api_config!
      params = { page_size: DEFAULT_PAGE_SIZE }
      params[:target] = target if target.present?
      get_paginated("#{API_PREFIX}/policies/bindings/", params)
    end

    def create_policy_binding(policy:, target:, order: 0, enabled: true, timeout: 30)
      validate_api_config!
      body = {
        policy: policy,
        target: target,
        order: order,
        enabled: enabled,
        timeout: timeout
      }

      post_json("#{API_PREFIX}/policies/bindings/", body)
    end

    def delete_policy_binding(binding_id)
      validate_api_config!
      delete_resource("#{API_PREFIX}/policies/bindings/#{binding_id}/")
    end

    # ========== Groups ==========

    def list_groups(name: nil)
      validate_api_config!
      params = { page_size: DEFAULT_PAGE_SIZE }
      params[:name] = name if name.present?
      get_paginated("#{API_PREFIX}/core/groups/", params)
    end

    def get_group(group_id)
      validate_api_config!
      response = connection.get("#{API_PREFIX}/core/groups/#{group_id}/")
      handle_error!(response)
      JSON.parse(response.body)
    end

    private

    def validate_api_config!
      raise ArgumentError, 'Authentik API token is missing' if @token.blank?
      raise ArgumentError, 'Authentik API base URL is missing' if @base_url.blank?
    end

    def connection
      @connection ||= Faraday.new(url: @base_url) do |faraday|
        faraday.request :authorization, 'Bearer', @token
        faraday.response :follow_redirects
        faraday.response :raise_error
        faraday.adapter Faraday.default_adapter
      end
    end

    def json_connection
      @json_connection ||= Faraday.new(url: @base_url) do |faraday|
        faraday.request :authorization, 'Bearer', @token
        faraday.request :json
        faraday.response :follow_redirects
        faraday.adapter Faraday.default_adapter
      end
    end

    def handle_error!(response)
      return if response.success?

      raise StandardError, "Authentik API error (#{response.status}): #{response.body}"
    end

    def get_paginated(path, params = {})
      results = []
      query = URI.encode_www_form(params)
      next_path = "#{path}?#{query}"

      while next_path.present?
        log_request(next_path)
        response = connection.get(next_path)
        handle_error!(response)

        payload = JSON.parse(response.body)
        results.concat(payload['results'] || [])

        next_link = payload['next']
        next_path = if next_link.is_a?(String) && next_link.start_with?('http')
                      URI(next_link).request_uri
                    elsif next_link.is_a?(String)
                      next_link
                    end
      end

      results
    end

    def post_json(path, body)
      log_request("POST #{path}")
      response = json_connection.post(path, body)
      handle_error!(response)
      JSON.parse(response.body)
    end

    def patch_json(path, body)
      log_request("PATCH #{path}")
      response = json_connection.patch(path, body)
      handle_error!(response)
      JSON.parse(response.body)
    end

    def delete_resource(path)
      log_request("DELETE #{path}")
      response = connection.delete(path)
      handle_error!(response)
      true
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
        username: user_data['username'] || user_data['preferred_username'] || entry['username'],
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
