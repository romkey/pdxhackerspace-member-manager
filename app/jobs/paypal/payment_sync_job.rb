module Paypal
  class PaymentSyncJob < ApplicationJob
    queue_as :default

    def perform
      count = Paypal::PaymentSynchronizer.new.call
      Rails.logger.info("Synced #{count} PayPal payments.")
    rescue StandardError => e
      Rails.logger.error("PayPal payment sync failed: #{e.class} #{e.message}")
      raise
    end
  end
end
