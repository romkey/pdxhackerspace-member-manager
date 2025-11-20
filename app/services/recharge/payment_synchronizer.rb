module Recharge
  class PaymentSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      raise ArgumentError, 'Recharge integration disabled' unless RechargeConfig.enabled?

      # Determine start_time based on existing transactions
      start_time = calculate_start_time

      charges = @client.charges(start_time: start_time)
      now = Time.current

      RechargePayment.transaction do
        charges.each do |attrs|
          # Only process transactions with status "SUCCESS"
          next unless attrs[:status] == 'SUCCESS'

          record = RechargePayment.find_or_initialize_by(recharge_id: attrs[:recharge_id])
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
          unless user
            user = find_user_by_email(attrs[:customer_email])

            # If we found a user by email, set the recharge_customer_id from the transaction
            if user && attrs[:customer_id].present? && user.recharge_customer_id != attrs[:customer_id]
              user.update!(recharge_customer_id: attrs[:customer_id])
            end
          end

          # If still no match, try to match by full name
          unless user
            user = find_user_by_name(attrs[:customer_name]) if attrs[:customer_name].present?

            # If we found a user by name, set the recharge_customer_id from the transaction
            if user && attrs[:customer_id].present? && user.recharge_customer_id != attrs[:customer_id]
              user.update!(recharge_customer_id: attrs[:customer_id])
            end
          end

          record.user = user
          record.sheet_entry = find_sheet_entry(attrs[:customer_email])
          record.save!

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

          # Update user payment_type and membership_status if payment is linked
          if user && attrs[:processed_at].present?
            payment_date = attrs[:processed_at].to_date
            update_user_from_payment(user, payment_date)
          end
        rescue ActiveRecord::RecordInvalid => e
          @logger.error("Failed to sync Recharge payment #{attrs[:recharge_id]}: #{e.message}")
        end
      end

      # Update User records with Recharge information
      update_user_recharge_fields

      charges.count
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

    def find_sheet_entry(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      SheetEntry.where('LOWER(email) = ?', normalized).first
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end

    def update_user_from_payment(user, payment_date)
      # Mark payment_type as recharge
      user.update!(payment_type: 'recharge') if user.payment_type != 'recharge'

      updates = {}

      # Update most recent payment date if this payment is more recent
      # Convert date to datetime for the datetime column
      payment_datetime = payment_date.to_datetime.beginning_of_day
      if user.recharge_most_recent_payment_date.nil? || payment_date > user.recharge_most_recent_payment_date.to_date
        updates[:recharge_most_recent_payment_date] = payment_datetime
      end

      # Update last_payment_date if this payment is more recent
      updates[:last_payment_date] = payment_date if user.last_payment_date.nil? || payment_date > user.last_payment_date

      # If payment is 1 month old or less, mark active as true and dues_status as current
      if payment_date >= 1.month.ago.to_date
        updates[:active] = true unless user.active?
        updates[:dues_status] = 'current' if user.dues_status != 'current'
      end

      user.update!(updates) if updates.any?
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

        payment_date = most_recent_payment.processed_at.to_date if most_recent_payment.processed_at

        updates = {
          recharge_most_recent_payment_date: most_recent_payment.processed_at,
          recharge_customer_id: customer_id.to_s.presence
        }

        # Update last_payment_date if this payment is more recent
        if payment_date && (user.last_payment_date.nil? || payment_date > user.last_payment_date)
          updates[:last_payment_date] = payment_date
        end

        user.update_columns(updates)

        # If most recent payment is 1 month old or less, ensure active is true and dues_status is current
        if payment_date && payment_date >= 1.month.ago.to_date
          status_updates = {}
          status_updates[:active] = true unless user.active?
          status_updates[:dues_status] = 'current' if user.dues_status != 'current'
          user.update!(status_updates) if status_updates.any?
        end
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
