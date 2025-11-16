module Recharge
  class PaymentSyncJob < ApplicationJob
    queue_as :default

    def perform
      count = Recharge::PaymentSynchronizer.new.call
      Rails.logger.info("Synced #{count} Recharge payments.")
    rescue StandardError => e
      Rails.logger.error("Recharge payment sync failed: #{e.class} #{e.message}")
      raise
    end
  end
end

