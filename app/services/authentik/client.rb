require 'uri'
require 'faraday/follow_redirects'

module Authentik
  class Client
    DEFAULT_PAGE_SIZE = 200

    API_PREFIX = '/api/v3'.freeze

    def initialize(base_url: AuthentikConfig.settings.api_base_url, token: nil)
      @base_url = base_url&.delete_suffix('/')
      @token = token || Authentik::TokenManager.token
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
        next_path = enforce_safe_relative_path!(next_path)
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

    # ========== Users ==========

    def get_user(user_pk)
      validate_api_config!
      response = connection.get("#{API_PREFIX}/core/users/#{user_pk}/")
      handle_error!(response)
      JSON.parse(response.body)
    end

    def find_user_by_username(username)
      validate_api_config!
      users = get_paginated("#{API_PREFIX}/core/users/", { username: username })
      users.find { |u| u['username'] == username }
    end

    def update_user(user_pk, **attrs)
      validate_api_config!
      patch_json("#{API_PREFIX}/core/users/#{user_pk}/", attrs)
    end

    def create_user(username:, name:, email: nil, is_active: true, attributes: {})
      validate_api_config!
      body = {
        username: username,
        name: name,
        is_active: is_active,
        attributes: attributes
      }
      body[:email] = email if email.present?

      post_json("#{API_PREFIX}/core/users/", body)
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

    # ========== Expression Policies ==========

    def list_expression_policies(search: nil)
      validate_api_config!
      params = { page_size: DEFAULT_PAGE_SIZE }
      params[:search] = search if search.present?
      get_paginated("#{API_PREFIX}/policies/expression/", params)
    end

    def find_expression_policy_by_name(name)
      policies = list_expression_policies(search: name)
      policies.find { |p| p['name'] == name }
    end

    def create_expression_policy(name:, expression:, execution_logging: false)
      validate_api_config!
      post_json("#{API_PREFIX}/policies/expression/", {
                  name: name,
                  expression: expression,
                  execution_logging: execution_logging
                })
    end

    def update_expression_policy(policy_id, **attrs)
      validate_api_config!
      patch_json("#{API_PREFIX}/policies/expression/#{policy_id}/", attrs)
    end

    def delete_expression_policy(policy_id)
      validate_api_config!
      delete_resource("#{API_PREFIX}/policies/expression/#{policy_id}/")
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

    def find_group_by_name(name)
      groups = list_groups(name: name)
      groups.find { |g| g['name'] == name }
    end

    def create_group(name:, attributes: {}, is_superuser: false, parent: nil, users: [])
      validate_api_config!
      body = {
        name: name,
        is_superuser: is_superuser,
        attributes: attributes
      }
      body[:parent] = parent if parent.present?
      body[:users] = users if users.present?

      post_json("#{API_PREFIX}/core/groups/", body)
    end

    def update_group(group_id, **attrs)
      validate_api_config!
      patch_json("#{API_PREFIX}/core/groups/#{group_id}/", attrs)
    end

    def delete_group(group_id)
      validate_api_config!
      delete_resource("#{API_PREFIX}/core/groups/#{group_id}/")
    end

    def add_user_to_group(group_id, user_pk)
      validate_api_config!
      log_request("POST #{API_PREFIX}/core/groups/#{group_id}/add_user/")
      response = json_connection.post("#{API_PREFIX}/core/groups/#{group_id}/add_user/", { pk: user_pk.to_i })
      # 204 No Content is success, but Faraday may return empty body
      return true if response.status == 204

      handle_error!(response)
      true
    end

    def remove_user_from_group(group_id, user_pk)
      validate_api_config!
      log_request("POST #{API_PREFIX}/core/groups/#{group_id}/remove_user/")
      response = json_connection.post("#{API_PREFIX}/core/groups/#{group_id}/remove_user/", { pk: user_pk.to_i })
      # 204 No Content is success
      return true if response.status == 204

      handle_error!(response)
      true
    end

    def set_group_users(group_id, user_pks)
      validate_api_config!
      # Update group with the complete list of user PKs
      update_group(group_id, users: user_pks.map(&:to_i))
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

      if [401, 403].include?(response.status)
        Rails.logger.error(
          'Authentik API auth failed — check AUTHENTIK_API_TOKEN is valid and has not expired'
        )
      end

      raise StandardError, "Authentik API error (#{response.status}): #{response.body}"
    end

    def get_paginated(path, params = {})
      results = []
      query = URI.encode_www_form(params)
      next_path = "#{path}?#{query}"

      while next_path.present?
        next_path = enforce_safe_relative_path!(next_path)
        log_request(next_path)
        response = connection.get(next_path)
        handle_error!(response)

        payload = JSON.parse(response.body)
        results.concat(payload['results'] || [])

        next_link = payload['next']
        next_path = (safe_relative_path(next_link) if next_link.is_a?(String) && next_link.present?)
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

      return safe_relative_path(next_link) if next_link.is_a?(String)

      if next_link.is_a?(Integer)
        return if next_link <= 0

        return build_user_path(base_params.merge(page: next_link))
      end

      nil
    end

    # Rejects protocol-relative URLs and absolute URLs so Faraday cannot be
    # directed to a host other than @base_url (defense in depth for CodeQL SSRF).
    def enforce_safe_relative_path!(path)
      raise ArgumentError, 'Authentik request path is blank' if path.blank?
      raise ArgumentError, 'Refusing protocol-relative Authentik path' if path.start_with?('//')
      raise ArgumentError, 'Refusing absolute URL as Authentik request path' if path.match?(/\A[a-z][a-z0-9+.-]*:/i)

      path
    end

    # Extracts the path+query from an absolute URL only if it belongs to the
    # same host/port as @base_url, preventing SSRF via API-response-supplied URLs.
    # Returns the string unchanged if it is already a relative path.
    def safe_relative_path(url_string)
      return url_string unless url_string.start_with?('http')

      parsed = URI.parse(url_string)
      configured = URI.parse(@base_url)

      unless parsed.host == configured.host && parsed.port == configured.port
        Rails.logger.warn(
          "[Authentik::Client] Rejecting next-page URL with unexpected host: #{parsed.host}:#{parsed.port}"
        )
        return nil
      end

      parsed.request_uri
    rescue URI::InvalidURIError => e
      Rails.logger.warn("[Authentik::Client] Invalid next-page URI '#{url_string}': #{e.message}")
      nil
    end

    def normalize_member(entry)
      user_data = member_user_data(entry)
      authentik_id = authentik_user_id(entry, user_data)
      user_data = hydrate_member_user_data(authentik_id, entry, user_data)

      {
        authentik_id: authentik_id.to_s,
        email: normalize_email(user_data['email'] || entry['email']),
        full_name: user_data['name'] || user_data['full_name'] ||
          [user_data['first_name'], user_data['last_name']].compact_blank.join(' '),
        username: user_data['username'] || user_data['preferred_username'] || entry['username'],
        active: !active_value(entry, user_data).in?([false, 'false']),
        attributes: extract_attributes(entry, user_data)
      }
    rescue NoMethodError
      nil
    end

    def member_user_data(entry)
      [
        entry['user_obj'],
        entry['user_object'],
        entry['user']
      ].find { |value| value.is_a?(Hash) } || entry
    end

    def authentik_user_id(entry, user_data)
      user_data['pk'] || user_data['id'] ||
        entry['user_pk'] || entry['user_id'] || entry['pk'] || entry['id']
    end

    def hydrate_member_user_data(authentik_id, entry, user_data)
      return user_data if authentik_id.blank?
      return user_data unless member_identity_incomplete?(entry, user_data)

      user_data.merge(get_user(authentik_id))
    rescue StandardError => e
      Rails.logger.warn("[Authentik::Client] Could not hydrate user #{authentik_id}: #{e.message}")
      user_data
    end

    def member_identity_incomplete?(entry, user_data)
      normalize_email(user_data['email'] || entry['email']).blank? ||
        (user_data['username'] || user_data['preferred_username'] || entry['username']).blank?
    end

    def active_value(entry, user_data)
      entry.key?('is_active') ? entry['is_active'] : user_data['is_active']
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
