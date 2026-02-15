module Paypal
  class PaymentSynchronizer
    include UserNameMatcher

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

      matched_count = 0
      unmatched_count = 0

      PaypalPayment.transaction do
        payments.each do |attrs|
          matches = membership_transaction?(attrs)

          unless matches
            subject = extract_transaction_subject(attrs)
            @logger.info { "[PayPal::PaymentSynchronizer] Payment #{attrs[:paypal_id]} does not match any plan - subject '#{subject}' (#{attrs[:payer_email]}, $#{attrs[:amount]} #{attrs[:currency]})" }
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
            last_synced_at: now,
            matches_plan: matches
          )
          # Only try to link users for payments that match a plan
          if matches
            user = find_user_by_payer_id(attrs[:payer_id]) ||
                   find_user_by_email(attrs[:payer_email]) ||
                   find_user_by_name(attrs[:payer_name])
            record.user = user
            matched_count += 1
          else
            unmatched_count += 1
          end
          record.save!
          saved_count += 1
          # The PaypalPayment after_save callback will call user.on_paypal_payment_linked
          # to handle payer ID, email, payment type, and membership status
        rescue ActiveRecord::RecordInvalid => e
          @logger.error("Failed to sync PayPal payment #{attrs[:paypal_id]}: #{e.message}")
        end
      end

      @logger.info("[PayPal::PaymentSynchronizer] Processed #{payments.count} transactions: #{saved_count} saved (#{matched_count} matched plans, #{unmatched_count} unmatched)")

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

    def find_user_by_payer_id(payer_id)
      return nil if payer_id.blank?
      
      User.find_by(paypal_account_id: payer_id)
    end

    def find_user_by_email(email)
      normalized_email = normalize_email(email)
      return nil if normalized_email.blank?

      # Match by primary email
      user = User.where('LOWER(email) = ?', normalized_email).first
      return user if user

      # Match by extra_emails array
      User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)',
                 normalized_email).first
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end

    # Get allowed transaction subjects from MembershipPlan records
    def allowed_transaction_subjects
      @allowed_transaction_subjects ||= MembershipPlan.with_transaction_subject
                                                      .pluck(:paypal_transaction_subject)
                                                      .compact
    end

    # Check if this transaction matches a payment plan by looking for transaction subjects in the raw attributes
    def membership_transaction?(attrs)
      return false if attrs[:raw_attributes].blank?

      subjects = allowed_transaction_subjects
      if subjects.empty?
        @logger.warn("[PayPal::PaymentSynchronizer] No payment plans have transaction subjects configured - skipping all payments")
        return false
      end

      # Convert raw_attributes to JSON string and search for allowed transaction subjects
      raw_json = attrs[:raw_attributes].to_json
      subjects.any? { |subject| raw_json.include?(subject) }
    end

    # Extract transaction subject from payment for logging
    def extract_transaction_subject(attrs)
      return 'unknown' if attrs[:raw_attributes].blank?
      
      # Try to find the transaction subject in common locations
      raw = attrs[:raw_attributes]
      raw.dig('transaction_info', 'transaction_subject') ||
        raw.dig('cart_info', 'item_details', 0, 'item_name') ||
        raw.dig('payer_info', 'payer_name', 'alternate_full_name') ||
        'unknown'
    end
  end
end
