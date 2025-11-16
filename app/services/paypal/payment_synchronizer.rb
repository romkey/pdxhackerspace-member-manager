module Paypal
  class PaymentSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      raise ArgumentError, "PayPal integration disabled" unless PaypalConfig.enabled?

      payments = @client.transactions
      now = Time.current

      PaypalPayment.transaction do
        payments.each do |attrs|
          record = PaypalPayment.find_or_initialize_by(paypal_id: attrs[:paypal_id])
          record.assign_attributes(
            status: attrs[:status],
            amount: attrs[:amount],
            currency: attrs[:currency],
            transaction_time: attrs[:transaction_time],
            transaction_type: attrs[:transaction_type],
            payer_email: attrs[:payer_email],
            payer_name: attrs[:payer_name],
            payer_id: attrs[:payer_id],
            raw_attributes: attrs[:raw_attributes],
            last_synced_at: now
          )
          record.user = find_user(attrs[:payer_email])
          record.sheet_entry = find_sheet_entry(attrs[:payer_email])
          record.save!
        rescue ActiveRecord::RecordInvalid => e
          @logger.error("Failed to sync PayPal payment #{attrs[:paypal_id]}: #{e.message}")
        end
      end

      payments.count
    end
    private

    def find_user(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      User.where("LOWER(email) = ?", normalized).first
    end

    def find_sheet_entry(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      SheetEntry.where("LOWER(email) = ?", normalized).first
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end
  end
end

