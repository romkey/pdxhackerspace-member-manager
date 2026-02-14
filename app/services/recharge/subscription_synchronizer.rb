# Periodically polls the Recharge API for subscription status changes.
# Acts as a safety net to catch events that may have been missed by webhooks
# (e.g., due to downtime or network issues).
#
# Detects new subscriptions (ACTIVE) and cancellations (CANCELLED),
# updating user membership_status and creating highlighted journal entries
# mirroring the behavior of Recharge::WebhookHandler.
module Recharge
  class SubscriptionSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      raise ArgumentError, 'Recharge integration disabled' unless RechargeConfig.enabled?

      subscriptions = fetch_subscriptions
      @logger.info("[Recharge::SubscriptionSynchronizer] Fetched #{subscriptions.size} recently updated subscriptions")

      stats = { created: 0, cancelled: 0, skipped: 0 }

      subscriptions.each do |sub|
        result = process_subscription(sub)
        stats[result] += 1
      end

      log_summary(stats)
      stats
    end

    private

    def fetch_subscriptions
      @client.subscriptions(start_time: lookback_time)
    end

    # Look back 48 hours to give plenty of overlap for catching missed webhooks.
    def lookback_time
      48.hours.ago
    end

    def process_subscription(sub)
      case sub[:status]&.upcase
      when 'ACTIVE'
        handle_active(sub)
      when 'CANCELLED'
        handle_cancelled(sub)
      else
        :skipped
      end
    end

    def handle_active(sub)
      user = find_user(sub)
      return :skipped unless user

      # Only act if the user is currently cancelled — don't override other statuses
      return :skipped unless user.cancelled?

      old_status = user.membership_status
      user.update!(membership_status: 'paying')
      link_customer_id(user, sub)
      create_journal_entry(user, 'subscription_created', sub, old_status, 'paying')

      @logger.info("[Recharge::SubscriptionSynchronizer] Re-activated #{user.display_name} (#{old_status} -> paying)")
      :created
    end

    def handle_cancelled(sub)
      user = find_user(sub)
      return :skipped unless user

      # Only act if the user is NOT already cancelled
      return :skipped if user.cancelled?

      old_status = user.membership_status
      user.update!(membership_status: 'cancelled')
      create_journal_entry(user, 'subscription_cancelled', sub, old_status, 'cancelled')

      @logger.info("[Recharge::SubscriptionSynchronizer] Cancelled #{user.display_name} (#{old_status} -> cancelled)")
      :cancelled
    end

    def find_user(sub)
      user = User.find_by(recharge_customer_id: sub[:customer_id]) if sub[:customer_id].present?
      user || find_user_by_email(sub[:email])
    end

    def find_user_by_email(email)
      return if email.blank?

      User.find_by('LOWER(email) = ?', email.to_s.strip.downcase)
    end

    def link_customer_id(user, sub)
      return if sub[:customer_id].blank?
      return if user.recharge_customer_id == sub[:customer_id]

      user.update!(recharge_customer_id: sub[:customer_id])
    end

    def create_journal_entry(user, action, sub, old_status, new_status)
      Journal.create!(
        user: user,
        action: action,
        changes_json: {
          action => {
            'source' => 'subscription_sync',
            'recharge_subscription_id' => sub[:recharge_subscription_id],
            'recharge_customer_id' => sub[:customer_id],
            'email' => sub[:email],
            'product_title' => sub[:product_title],
            'price' => sub[:price],
            'previous_membership_status' => old_status,
            'new_membership_status' => new_status,
            'cancellation_reason' => sub[:cancellation_reason],
            'cancelled_at' => sub[:cancelled_at]&.iso8601
          }.compact
        },
        changed_at: Time.current,
        highlight: true
      )
    end

    def log_summary(stats)
      @logger.info(
        "[Recharge::SubscriptionSynchronizer] Done: " \
        "#{stats[:created]} activated, #{stats[:cancelled]} cancelled, #{stats[:skipped]} skipped"
      )
    end
  end
end
