module Recharge
  # Handles incoming Recharge subscription webhook events.
  # Processes subscription/created and subscription/cancelled topics,
  # updating user membership status and creating highlighted journal entries.
  class WebhookHandler
    SUPPORTED_TOPICS = %w[subscription/created subscription/cancelled].freeze

    def initialize(topic:, payload:)
      @topic = topic
      @payload = payload
      @subscription = payload['subscription'] || {}
    end

    def call
      unless SUPPORTED_TOPICS.include?(@topic)
        Rails.logger.info("[Recharge::WebhookHandler] Ignoring unsupported topic: #{@topic}")
        return { status: 'ignored', reason: "unsupported topic: #{@topic}" }
      end

      case @topic
      when 'subscription/created'
        handle_subscription_created
      when 'subscription/cancelled'
        handle_subscription_cancelled
      end
    end

    private

    def handle_subscription_created
      user = find_user
      return user_not_found('subscription/created') unless user

      old_status = user.membership_status
      user.update!(membership_status: 'paying') if user.cancelled?
      user.update!(recharge_customer_id: customer_id) if link_customer_id?(user)

      details = { 'previous_membership_status' => old_status,
                  'new_membership_status' => user.reload.membership_status }
      create_journal_entry(user: user, action: 'subscription_created', details: details)
      log_and_respond('subscription/created', user, old_status, user.membership_status)
    end

    def handle_subscription_cancelled
      user = find_user
      return user_not_found('subscription/cancelled') unless user

      old_status = user.membership_status
      # Mark as cancelled but do NOT change active, dues_status, or access.
      # Access continues until they lapse; cancelled members get no grace period.
      user.update!(membership_status: 'cancelled') unless user.cancelled?

      details = { 'previous_membership_status' => old_status,
                  'cancellation_reason' => @subscription['cancellation_reason'],
                  'cancelled_at' => @subscription['cancelled_at'] }
      create_journal_entry(user: user, action: 'subscription_cancelled', details: details)
      log_and_respond('subscription/cancelled', user, old_status, 'cancelled')
    end

    def link_customer_id?(user)
      customer_id.present? && user.recharge_customer_id != customer_id
    end

    def user_not_found(topic)
      Rails.logger.warn("[Recharge::WebhookHandler] #{topic}: no user found for #{identifier_summary}")
      { status: 'skipped', reason: 'user not found' }
    end

    def log_and_respond(topic, user, old_status, new_status)
      Rails.logger.info("[Recharge::WebhookHandler] #{topic}: #{user.display_name} (#{old_status} -> #{new_status})")
      { status: 'processed', user_id: user.id, action: topic.tr('/', '_') }
    end

    def find_user
      (customer_id.present? && User.find_by(recharge_customer_id: customer_id)) ||
        (subscription_email.present? && User.find_by('LOWER(email) = ?', subscription_email.downcase))
    end

    def customer_id
      @customer_id ||= @subscription['customer_id']&.to_s
    end

    def subscription_email
      @subscription_email ||= @subscription['email']
    end

    def identifier_summary
      [("customer_id=#{customer_id}" if customer_id.present?),
       ("email=#{subscription_email}" if subscription_email.present?)].compact.join(', ')
    end

    def create_journal_entry(user:, action:, details:)
      Journal.create!(
        user: user,
        action: action,
        changes_json: { action => subscription_summary.merge(details) },
        changed_at: Time.current,
        highlight: true
      )
    end

    def subscription_summary
      {
        'recharge_subscription_id' => @subscription['id'],
        'recharge_customer_id' => customer_id,
        'email' => subscription_email,
        'product_title' => @subscription['product_title'],
        'status' => @subscription['status'],
        'price' => @subscription['price']
      }.compact
    end
  end
end
