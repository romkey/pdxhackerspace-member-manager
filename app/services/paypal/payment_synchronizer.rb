module Paypal
  class PaymentSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      raise ArgumentError, 'PayPal integration disabled' unless PaypalConfig.enabled?

      processor = PaymentProcessor.for('paypal')

      # Calculate start_time: 3 days before the most recent payment, or use default if no payments exist
      start_time = calculate_start_time

      begin
        payments = @client.transactions(start_time: start_time)
      rescue Faraday::ForbiddenError => e
        @logger.error('PayPal API returned 403 Forbidden - NOT_AUTHORIZED')
        @logger.error("This means your PayPal app doesn't have permission to access the Reporting API.")
        @logger.error('')
        @logger.error('To fix this, you need to:')
        @logger.error('  1. Go to https://developer.paypal.com/dashboard')
        @logger.error('  2. Select your app (or create a new one)')
        @logger.error("  3. Under 'Features', enable 'Transaction Search' or 'Reporting API'")
        @logger.error("  4. Make sure your app has 'Read transaction details' permission")
        @logger.error('  5. Regenerate your client secret if needed')
        @logger.error('')
        if e.respond_to?(:response) && e.response
          @logger.error("Response body: #{e.response[:body]}")
        elsif e.respond_to?(:message)
          @logger.error("Error message: #{e.message}")
        end
        processor.record_failed_sync!(e.message)
        raise
      rescue StandardError => e
        processor.record_failed_sync!(e.message)
        raise
      end
      now = Time.current
      saved_count = 0
      skipped_count = 0

      PaypalPayment.transaction do
        payments.each do |attrs|
          # Only import transactions that contain allowed subjects (membership, storage, support)
          unless membership_transaction?(attrs)
            skipped_count += 1
            @logger.debug { "[PayPal::PaymentSynchronizer] Skipping non-membership transaction #{attrs[:paypal_id]}" }
            next
          end

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
          user = find_user(attrs[:payer_email], attrs[:payer_name])
          record.user = user
          record.save!
          saved_count += 1
          # The PaypalPayment after_save callback will call user.on_paypal_payment_linked
          # to handle payer ID, email, payment type, and membership status
        rescue ActiveRecord::RecordInvalid => e
          @logger.error("Failed to sync PayPal payment #{attrs[:paypal_id]}: #{e.message}")
        end
      end

      @logger.info("[PayPal::PaymentSynchronizer] Processed #{payments.count} transactions: #{saved_count} membership payments saved, #{skipped_count} non-membership skipped")

      processor.record_successful_sync!(saved_count)
      saved_count
    end

    private

    def calculate_start_time
      # Find the most recent payment
      most_recent_payment = PaypalPayment.where.not(transaction_time: nil)
                                         .order(transaction_time: :desc)
                                         .first

      if most_recent_payment&.transaction_time
        # Start 3 days before the most recent payment
        start_time = most_recent_payment.transaction_time - 3.days
        @logger.info("[PayPal::PaymentSynchronizer] Most recent payment: #{most_recent_payment.transaction_time}, requesting from: #{start_time}")
        start_time
      else
        # No payments exist, use default lookback
        days = PaypalConfig.settings.transactions_lookback_days
        days = 30 if days <= 0
        default_start = Time.current - days.days
        @logger.info("[PayPal::PaymentSynchronizer] No existing payments, using default lookback: #{days} days from now (#{default_start})")
        default_start
      end
    end

    def find_user(email, name = nil)
      normalized_email = normalize_email(email)
      normalized_name = name.to_s.strip.downcase.presence

      # Try to find by email first (primary email or extra_emails)
      if normalized_email.present?
        # Match by primary email
        user = User.where('LOWER(email) = ?', normalized_email).first
        return user if user

        # Match by extra_emails array
        user = User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)',
                          normalized_email).first
        return user if user
      end

      # Try to find by name if email didn't match
      if normalized_name.present?
        user = User.where('LOWER(full_name) = ?', normalized_name).first
        return user if user
      end

      nil
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end

    # Check if this transaction is a relevant payment by looking for known subjects in the raw attributes
    ALLOWED_TRANSACTION_SUBJECTS = [
      'CTRL-H Membership',
      'Storage Space',
      'Monthly Support'
    ].freeze

    def membership_transaction?(attrs)
      return false if attrs[:raw_attributes].blank?

      # Convert raw_attributes to JSON string and search for allowed transaction subjects
      raw_json = attrs[:raw_attributes].to_json
      ALLOWED_TRANSACTION_SUBJECTS.any? { |subject| raw_json.include?(subject) }
    end
  end
end
