module Recharge
  class PaymentSynchronizer
    def initialize(client: Client.new, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def call
      raise ArgumentError, "Recharge integration disabled" unless RechargeConfig.enabled?

      charges = @client.charges
      now = Time.current

      RechargePayment.transaction do
        charges.each do |attrs|
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
          
          # First try to match by customer_id
          user = find_user_by_customer_id(attrs[:customer_id]) if attrs[:customer_id].present?
          
          # If no match by customer_id, try name and email
          unless user
            user = find_user_by_email(attrs[:customer_email])
            user ||= find_user_by_name(attrs[:customer_name]) if attrs[:customer_name].present?
            
            # If we found a user by name/email, copy the customer_id to the user
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
              action: "updated",
              changes_json: {
                "recharge_payment_linked" => {
                  "from" => nil,
                  "to" => {
                    "recharge_id" => record.recharge_id,
                    "amount" => record.amount,
                    "currency" => record.currency,
                    "processed_at" => record.processed_at&.iso8601
                  }
                }
              },
              changed_at: Time.current
            )
          end
          
          # Update user payment_type and membership_status if payment is linked
          if user && attrs[:processed_at].present?
            update_user_from_payment(user, attrs[:processed_at])
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

    def find_user_by_customer_id(customer_id)
      return if customer_id.blank?
      
      User.where(recharge_customer_id: customer_id.to_s).first
    end

    def find_user_by_email(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      # Match by primary email
      user = User.where("LOWER(email) = ?", normalized).first
      return user if user

      # Match by extra_emails array (check if email exists in the array, case-insensitive)
      User.where("EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)", normalized).first
    end

    def find_user_by_name(name)
      return if name.blank?
      
      normalized_name = name.to_s.strip.downcase
      return if normalized_name.blank?
      
      User.where("LOWER(full_name) = ?", normalized_name).first
    end

    def find_sheet_entry(email)
      normalized = normalize_email(email)
      return if normalized.blank?

      SheetEntry.where("LOWER(email) = ?", normalized).first
    end

    def normalize_email(value)
      value.to_s.strip.downcase
    end

    def update_user_from_payment(user, payment_date)
      # Mark payment_type as recharge
      if user.payment_type != "recharge"
        user.update!(payment_type: "recharge")
      end
      
      # Update most recent payment date if this payment is more recent
      if user.recharge_most_recent_payment_date.nil? || payment_date > user.recharge_most_recent_payment_date
        user.update!(recharge_most_recent_payment_date: payment_date)
        
        # If payment is less than a month old, mark membership_status as active and dues_status as current
        if payment_date > 1.month.ago
          updates = {}
          if user.membership_status != "active"
            updates[:membership_status] = "active"
          end
          if user.dues_status != "current"
            updates[:dues_status] = "current"
          end
          user.update!(updates) if updates.any?
        end
      end
    end

    def update_user_recharge_fields
      # Group payments by user and find the most recent payment for each
      User.joins(:recharge_payments).distinct.find_each do |user|
        most_recent_payment = user.recharge_payments
                                   .where.not(processed_at: nil)
                                   .order(processed_at: :desc)
                                   .first

        next unless most_recent_payment

        # Extract order number from raw_attributes (could be order_id, order_number, or charge id)
        order_number = most_recent_payment.raw_attributes["order_id"] ||
                       most_recent_payment.raw_attributes["order_number"] ||
                       most_recent_payment.raw_attributes["order"] ||
                       most_recent_payment.recharge_id

        # Extract customer_id from raw_attributes if available
        customer_id = most_recent_payment.raw_attributes.dig("customer", "id") ||
                      most_recent_payment.raw_attributes["customer_id"] ||
                      user.recharge_customer_id

        user.update_columns(
          recharge_name: most_recent_payment.customer_name,
          recharge_email: most_recent_payment.customer_email,
          recharge_order_number: order_number.to_s,
          recharge_most_recent_payment_date: most_recent_payment.processed_at,
          recharge_customer_id: customer_id.to_s.presence
        )
        
        # If most recent payment is less than a month old, ensure membership_status is active and dues_status is current
        if most_recent_payment.processed_at && most_recent_payment.processed_at > 1.month.ago
          updates = {}
          if user.membership_status != "active"
            updates[:membership_status] = "active"
          end
          if user.dues_status != "current"
            updates[:dues_status] = "current"
          end
          user.update!(updates) if updates.any?
        end
      end

      # Also update users who have no Recharge payments (clear their fields)
      users_without_payments = User.left_joins(:recharge_payments)
                                    .where(recharge_payments: { id: nil })
                                    .where("recharge_name IS NOT NULL OR recharge_email IS NOT NULL OR recharge_order_number IS NOT NULL OR recharge_most_recent_payment_date IS NOT NULL")
      
      users_without_payments.update_all(
        recharge_name: nil,
        recharge_email: nil,
        recharge_order_number: nil,
        recharge_most_recent_payment_date: nil
      )
    end
  end
end

