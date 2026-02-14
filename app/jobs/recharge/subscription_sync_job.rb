# Periodic job to poll the Recharge API for subscription status changes.
# Serves as a safety net for missed webhooks.
module Recharge
  class SubscriptionSyncJob < ApplicationJob
    queue_as :default

    def perform
      stats = Recharge::SubscriptionSynchronizer.new.call
      Rails.logger.info(
        "[Recharge::SubscriptionSyncJob] Completed: " \
        "#{stats[:created]} activated, #{stats[:cancelled]} cancelled, #{stats[:skipped]} skipped"
      )
    rescue StandardError => e
      Rails.logger.error("[Recharge::SubscriptionSyncJob] Failed: #{e.class} #{e.message}")
      raise
    end
  end
end
