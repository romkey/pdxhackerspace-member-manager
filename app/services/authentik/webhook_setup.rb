module Authentik
  class WebhookSetup
    TRANSPORT_NAME = 'MemberManager Webhook'.freeze
    USER_POLICY_NAME = 'MemberManager User Events'.freeze
    GROUP_POLICY_NAME = 'MemberManager Group Events'.freeze
    RULE_NAME = 'MemberManager Notifications'.freeze

    attr_reader :client, :webhook_url, :webhook_secret, :admin_group_id

    def initialize(
      webhook_url: nil,
      webhook_secret: AuthentikConfig.settings.webhook_secret,
      admin_group_id: AuthentikConfig.settings.group_id
    )
      @client = Authentik::Client.new
      @webhook_url = webhook_url || default_webhook_url
      @webhook_secret = webhook_secret
      @admin_group_id = admin_group_id
    end

    def setup!
      Rails.logger.info('[Authentik WebhookSetup] Starting webhook configuration...')

      validate_configuration!

      transport = setup_transport!
      user_policy = setup_user_policy!
      group_policy = setup_group_policy!
      rule = setup_notification_rule!(transport)
      bind_policies_to_rule!(rule, [user_policy, group_policy])

      result = {
        success: true,
        transport: transport,
        user_policy: user_policy,
        group_policy: group_policy,
        rule: rule
      }

      Rails.logger.info('[Authentik WebhookSetup] Webhook configuration completed successfully')
      result
    rescue StandardError => e
      Rails.logger.error("[Authentik WebhookSetup] Setup failed: #{e.message}")
      { success: false, error: e.message }
    end

    def teardown!
      Rails.logger.info('[Authentik WebhookSetup] Starting webhook teardown...')

      # Delete in reverse order of dependencies
      delete_notification_rule!
      delete_policies!
      delete_transport!

      Rails.logger.info('[Authentik WebhookSetup] Webhook teardown completed')
      { success: true }
    rescue StandardError => e
      Rails.logger.error("[Authentik WebhookSetup] Teardown failed: #{e.message}")
      { success: false, error: e.message }
    end

    def status
      transport = find_transport
      user_policy = find_policy(USER_POLICY_NAME)
      group_policy = find_policy(GROUP_POLICY_NAME)
      rule = find_rule

      {
        configured: transport.present? && rule.present?,
        transport: transport ? { id: transport['pk'], name: transport['name'], webhook_url: transport['webhook_url'] } : nil,
        user_policy: user_policy ? { id: user_policy['pk'], name: user_policy['name'] } : nil,
        group_policy: group_policy ? { id: group_policy['pk'], name: group_policy['name'] } : nil,
        rule: rule ? { id: rule['pk'], name: rule['name'] } : nil
      }
    end

    private

    def default_webhook_url
      base_url = ENV['MEMBER_MANAGER_BASE_URL']
      return nil if base_url.blank?

      "#{base_url.delete_suffix('/')}/webhooks/authentik"
    end

    def validate_configuration!
      raise ArgumentError, 'Webhook URL is required. Set MEMBER_MANAGER_BASE_URL environment variable.' if webhook_url.blank?
      raise ArgumentError, 'Admin group ID is required for notification rule binding.' if admin_group_id.blank?
    end

    # ========== Transport ==========

    def setup_transport!
      existing = find_transport
      if existing
        Rails.logger.info("[Authentik WebhookSetup] Updating existing transport: #{existing['pk']}")
        client.update_notification_transport(
          existing['pk'],
          webhook_url: build_webhook_url,
          mode: 'webhook'
        )
      else
        Rails.logger.info('[Authentik WebhookSetup] Creating new transport')
        client.create_notification_transport(
          name: TRANSPORT_NAME,
          mode: 'webhook',
          webhook_url: build_webhook_url
        )
      end
    end

    def find_transport
      transports = client.list_notification_transports(name: TRANSPORT_NAME)
      transports.find { |t| t['name'] == TRANSPORT_NAME }
    end

    def delete_transport!
      transport = find_transport
      return unless transport

      Rails.logger.info("[Authentik WebhookSetup] Deleting transport: #{transport['pk']}")
      client.delete_notification_transport(transport['pk'])
    end

    def build_webhook_url
      url = webhook_url
      if webhook_secret.present?
        separator = url.include?('?') ? '&' : '?'
        url = "#{url}#{separator}secret=#{webhook_secret}"
      end
      url
    end

    # ========== Policies ==========

    def setup_user_policy!
      existing = find_policy(USER_POLICY_NAME)
      if existing
        Rails.logger.info("[Authentik WebhookSetup] User policy already exists: #{existing['pk']}")
        existing
      else
        Rails.logger.info('[Authentik WebhookSetup] Creating user event matcher policy')
        client.create_event_matcher_policy(
          name: USER_POLICY_NAME,
          app: 'authentik.core',
          model: 'authentik_core.user'
        )
      end
    end

    def setup_group_policy!
      existing = find_policy(GROUP_POLICY_NAME)
      if existing
        Rails.logger.info("[Authentik WebhookSetup] Group policy already exists: #{existing['pk']}")
        existing
      else
        Rails.logger.info('[Authentik WebhookSetup] Creating group event matcher policy')
        client.create_event_matcher_policy(
          name: GROUP_POLICY_NAME,
          app: 'authentik.core',
          model: 'authentik_core.group'
        )
      end
    end

    def find_policy(name)
      policies = client.list_event_matcher_policies(name: name)
      policies.find { |p| p['name'] == name }
    end

    def delete_policies!
      [USER_POLICY_NAME, GROUP_POLICY_NAME].each do |policy_name|
        policy = find_policy(policy_name)
        next unless policy

        # First delete any bindings for this policy
        bindings = client.list_policy_bindings
        policy_bindings = bindings.select { |b| b['policy'] == policy['pk'] }
        policy_bindings.each do |binding|
          Rails.logger.info("[Authentik WebhookSetup] Deleting policy binding: #{binding['pk']}")
          client.delete_policy_binding(binding['pk'])
        end

        Rails.logger.info("[Authentik WebhookSetup] Deleting policy: #{policy['pk']}")
        client.delete_event_matcher_policy(policy['pk'])
      end
    end

    # ========== Notification Rule ==========

    def setup_notification_rule!(transport)
      existing = find_rule
      if existing
        Rails.logger.info("[Authentik WebhookSetup] Updating existing notification rule: #{existing['pk']}")
        client.update_notification_rule(
          existing['pk'],
          transports: [transport['pk']],
          group: admin_group_id
        )
      else
        Rails.logger.info('[Authentik WebhookSetup] Creating notification rule')
        client.create_notification_rule(
          name: RULE_NAME,
          transports: [transport['pk']],
          group: admin_group_id,
          severity: 'notice'
        )
      end
    end

    def find_rule
      rules = client.list_notification_rules(name: RULE_NAME)
      rules.find { |r| r['name'] == RULE_NAME }
    end

    def delete_notification_rule!
      rule = find_rule
      return unless rule

      Rails.logger.info("[Authentik WebhookSetup] Deleting notification rule: #{rule['pk']}")
      client.delete_notification_rule(rule['pk'])
    end

    # ========== Policy Bindings ==========

    def bind_policies_to_rule!(rule, policies)
      existing_bindings = client.list_policy_bindings(target: rule['pk'])

      policies.each_with_index do |policy, index|
        already_bound = existing_bindings.any? { |b| b['policy'] == policy['pk'] }
        if already_bound
          Rails.logger.info("[Authentik WebhookSetup] Policy #{policy['name']} already bound to rule")
          next
        end

        Rails.logger.info("[Authentik WebhookSetup] Binding policy #{policy['name']} to rule")
        client.create_policy_binding(
          policy: policy['pk'],
          target: rule['pk'],
          order: index
        )
      end
    end
  end
end
