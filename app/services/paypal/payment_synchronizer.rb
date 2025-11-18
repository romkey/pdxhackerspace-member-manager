module Paypal
  class PaymentSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      raise ArgumentError, "PayPal integration disabled" unless PaypalConfig.enabled?

      begin
        payments = @client.transactions
      rescue Faraday::ForbiddenError => e
        @logger.error("PayPal API returned 403 Forbidden - NOT_AUTHORIZED")
        @logger.error("This means your PayPal app doesn't have permission to access the Reporting API.")
        @logger.error("")
        @logger.error("To fix this, you need to:")
        @logger.error("  1. Go to https://developer.paypal.com/dashboard")
        @logger.error("  2. Select your app (or create a new one)")
        @logger.error("  3. Under 'Features', enable 'Transaction Search' or 'Reporting API'")
        @logger.error("  4. Make sure your app has 'Read transaction details' permission")
        @logger.error("  5. Regenerate your client secret if needed")
        @logger.error("")
        if e.respond_to?(:response) && e.response
          @logger.error("Response body: #{e.response[:body]}")
        elsif e.respond_to?(:message)
          @logger.error("Error message: #{e.message}")
        end
        raise
      end
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

