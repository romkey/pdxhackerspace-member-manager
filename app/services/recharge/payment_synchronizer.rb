module Recharge
  class PaymentSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      raise ArgumentError, 'Recharge integration disabled' unless RechargeConfig.enabled?

      processor = PaymentProcessor.for('recharge')

      # Determine start_time based on existing transactions
      start_time = calculate_start_time

      begin
        charges = @client.charges(start_time: start_time)
      rescue StandardError => e
        processor.record_failed_sync!(e.message)
        raise
      end

      now = Time.current

      # Count statistics for debugging
      status_counts = charges.group_by { |c| c[:status] }.transform_values(&:count)
      @logger.info("[Recharge::PaymentSynchronizer] Charge status breakdown: #{status_counts.inspect}")

      saved_count = 0
      skipped_count = 0

      RechargePayment.transaction do
        charges.each do |attrs|
          # Only process transactions with status "SUCCESS"
          unless attrs[:status] == 'SUCCESS'
            skipped_count += 1
            @logger.debug { "[Recharge::PaymentSynchronizer] Skipping charge #{attrs[:recharge_id]} with status #{attrs[:status]}" }
            next
          end

          record = RechargePayment.find_or_initialize_by(recharge_id: attrs[:recharge_id])
          is_new = record.new_record?
          record.assign_attributes(
            status: attrs[:status],
            amount: attrs[:amount],
            currency: attrs[:currency],
            processed_at: attrs[:processed_at],
            charge_type: attrs[:charge_type],
            customer_email: attrs[:customer_email],
            customer_name: attrs[:customer_name],
            raw_attributes: attrs[:raw_attributes],
            last_synced_at: now
          )
          user_was_linked = record.user_id.present?

          # First try to match by customer_id - if there's a matching recharge_customer_id, we're all set
          user = find_user_by_customer_id(attrs[:customer_id]) if attrs[:customer_id].present?

          # If no match by customer_id, try to match by email address
          user ||= find_user_by_email(attrs[:customer_email])

          # If still no match, try to match by full name
          user ||= find_user_by_name(attrs[:customer_name]) if attrs[:customer_name].present?

          # Note: The RechargePayment after_save callback will handle setting
          # recharge_customer_id on the user when the payment is linked

          record.user = user
          record.save!
          # The RechargePayment after_save callback will call user.on_recharge_payment_linked
          # to handle customer ID, email, payment type, and membership status
          saved_count += 1

          if is_new
            @logger.debug { "[Recharge::PaymentSynchronizer] Created new payment: #{attrs[:recharge_id]} - #{attrs[:customer_email]} - #{attrs[:amount]} #{attrs[:currency]} - processed #{attrs[:processed_at]}" }
          end

          # Create journal entry if payment was just linked to a user
          if user && !user_was_linked && record.user_id.present?
            Journal.create!(
              user: user,
              actor_user: Current.user,
              action: 'updated',
              changes_json: {
                'recharge_payment_linked' => {
                  'from' => nil,
                  'to' => {
                    'recharge_id' => record.recharge_id,
                    'amount' => record.amount,
                    'currency' => record.currency,
                    'processed_at' => record.processed_at&.iso8601
                  }
                }
              },
              changed_at: Time.current
            )
          end
        rescue ActiveRecord::RecordInvalid => e
          @logger.error("[Recharge::PaymentSynchronizer] Failed to sync payment #{attrs[:recharge_id]}: #{e.message}")
        end
      end

      @logger.info("[Recharge::PaymentSynchronizer] Processed #{charges.count} charges: #{saved_count} saved, #{skipped_count} skipped (non-SUCCESS status)")

      # Update User records with Recharge information
      update_user_recharge_fields

      processor.record_successful_sync!(saved_count)
      saved_count
    end

    private

    def calculate_start_time
      # If there are no transactions, use the configured lookback days
      most_recent_payment = RechargePayment.order(processed_at: :desc).first

      if most_recent_payment.nil? || most_recent_payment.processed_at.nil?
        # No transactions or no processed_at date, use default lookback
        days = RechargeConfig.settings.transactions_lookback_days
        days = 30 if days <= 0
        return Time.current - days.days
      end

      # Calculate how many days ago the most recent transaction was
      days_ago = ((Time.current - most_recent_payment.processed_at) / 1.day).ceil

      # Add 3 days to that
      lookback_days = days_ago + 3

      @logger.info("[Recharge::PaymentSynchronizer] Most recent payment was #{days_ago} days ago, looking back #{lookback_days} days")

      Time.current - lookback_days.days
    end

    def find_user_by_customer_id(customer_id)
      return if customer_id.blank?

      User.where(recharge_customer_id: customer_id.to_s).first
    end

    def find_user_by_email(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      # Match by primary email
      user = User.where('LOWER(email) = ?', normalized).first
      return user if user

      # Match by extra_emails array (check if email exists in the array, case-insensitive)
      User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)', normalized).first
    end

    def find_user_by_name(name)
      return if name.blank?

      normalized_name = name.to_s.strip.downcase
      return if normalized_name.blank?

      User.where('LOWER(full_name) = ?', normalized_name).first
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end

    def update_user_recharge_fields
      # Group payments by user and find the most recent payment for each
      User.joins(:recharge_payments).distinct.find_each do |user|
        most_recent_payment = user.recharge_payments
                                  .where.not(processed_at: nil)
                                  .order(processed_at: :desc)
                                  .first

        next unless most_recent_payment

        # Extract customer_id from raw_attributes if available
        customer_id = most_recent_payment.raw_attributes.dig('customer', 'id') ||
                      most_recent_payment.raw_attributes['customer_id'] ||
                      user.recharge_customer_id

        # Use update_columns for the Recharge-specific fields (bypasses callbacks)
        user.update_columns(
          recharge_most_recent_payment_date: most_recent_payment.processed_at,
          recharge_customer_id: customer_id.to_s.presence
        )

        # Use shared method for payment-related membership updates (pass amount for plan matching)
        updates = user.apply_payment_updates({ time: most_recent_payment.processed_at, amount: most_recent_payment.amount })
        user.update!(updates) if updates.any?
      end

      # Also update users who have no Recharge payments (clear their fields)
      users_without_payments = User.where.missing(:recharge_payments)
                                   .where('recharge_most_recent_payment_date IS NOT NULL OR recharge_customer_id IS NOT NULL')

      users_without_payments.update_all(
        recharge_most_recent_payment_date: nil,
        recharge_customer_id: nil
      )
    end
  end
end
