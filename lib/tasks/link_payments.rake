namespace :payments do
  desc "Set user_id on PayPal and Recharge payments based on payer/customer ID matches, and set membership dates"
  task link: :environment do
    puts "=" * 60
    puts "Linking payments to users"
    puts "=" * 60

    # Build lookup hashes for efficiency
    puts "\nBuilding user lookup tables..."

    # PayPal: user.paypal_account_id => user.id
    paypal_user_map = User.where.not(paypal_account_id: [nil, ''])
                          .pluck(:paypal_account_id, :id)
                          .to_h
    puts "  Found #{paypal_user_map.size} users with PayPal account IDs"

    # Recharge: user.recharge_customer_id => user.id
    recharge_user_map = User.where.not(recharge_customer_id: [nil, ''])
                            .pluck(:recharge_customer_id, :id)
                            .to_h
    puts "  Found #{recharge_user_map.size} users with Recharge customer IDs"

    # Process PayPal payments
    puts "\n" + "-" * 60
    puts "Processing PayPal payments..."

    paypal_updated = 0
    paypal_skipped = 0
    paypal_no_match = 0

    PaypalPayment.where(user_id: nil).where.not(payer_id: [nil, '']).find_each do |payment|
      user_id = paypal_user_map[payment.payer_id]

      if user_id
        # Use update_column to skip callbacks (avoid triggering on_paypal_payment_linked)
        payment.update_column(:user_id, user_id)
        paypal_updated += 1
      else
        paypal_no_match += 1
      end
    end

    # Count already linked
    paypal_already_linked = PaypalPayment.where.not(user_id: nil).count

    puts "  Already linked: #{paypal_already_linked}"
    puts "  Newly linked: #{paypal_updated}"
    puts "  No matching user: #{paypal_no_match}"

    # Process Recharge payments
    puts "\n" + "-" * 60
    puts "Processing Recharge payments..."

    recharge_updated = 0
    recharge_skipped = 0
    recharge_no_match = 0

    RechargePayment.where(user_id: nil).where.not(customer_id: [nil, '']).find_each do |payment|
      user_id = recharge_user_map[payment.customer_id]

      if user_id
        # Use update_column to skip callbacks (avoid triggering on_recharge_payment_linked)
        payment.update_column(:user_id, user_id)
        recharge_updated += 1
      else
        recharge_no_match += 1
      end
    end

    # Count already linked
    recharge_already_linked = RechargePayment.where.not(user_id: nil).count

    puts "  Already linked: #{recharge_already_linked}"
    puts "  Newly linked: #{recharge_updated}"
    puts "  No matching user: #{recharge_no_match}"

    # Set membership dates
    puts "\n" + "-" * 60
    puts "Setting membership dates..."
    update_membership_dates

    # Summary
    puts "\n" + "=" * 60
    puts "SUMMARY"
    puts "=" * 60
    puts "PayPal payments linked: #{paypal_updated}"
    puts "Recharge payments linked: #{recharge_updated}"
    puts "Total payments linked: #{paypal_updated + recharge_updated}"
    puts "\nDone!"
  end

  # Helper method to update membership dates for all users with payments
  def update_membership_dates
    users_updated = 0
    users_skipped = 0

    User.find_each do |user|
      # Collect all payment dates for this user
      paypal_dates = user.paypal_payments.where.not(transaction_time: nil).order(:transaction_time).pluck(:transaction_time)
      recharge_dates = user.recharge_payments.where.not(processed_at: nil).order(:processed_at).pluck(:processed_at)

      # Skip if no payments
      if paypal_dates.empty? && recharge_dates.empty?
        users_skipped += 1
        next
      end

      updates = {}

      # Find earliest payment of each type
      earliest_paypal = paypal_dates.first
      earliest_recharge = recharge_dates.first

      # Determine membership_start_date:
      # Set to 1 month after the first payment of whichever type came first
      if earliest_paypal.present? && earliest_recharge.present?
        earliest_payment = [earliest_paypal, earliest_recharge].min
      else
        earliest_payment = earliest_paypal || earliest_recharge
      end

      if earliest_payment.present?
        start_date = (earliest_payment + 1.month).to_date
        updates[:membership_start_date] = start_date if user.membership_start_date.nil?
      end

      # Find most recent payment of each type
      latest_paypal = paypal_dates.last
      latest_recharge = recharge_dates.last

      # Determine membership_ended_date:
      # Set to 1 month after the last payment, unless the last payment is within 32 days of now
      if latest_paypal.present? && latest_recharge.present?
        latest_payment = [latest_paypal, latest_recharge].max
      else
        latest_payment = latest_paypal || latest_recharge
      end

      if latest_payment.present?
        # Only set membership_ended_date if last payment is older than 32 days
        if latest_payment.to_date < 32.days.ago.to_date
          ended_date = (latest_payment + 1.month).to_date
          updates[:membership_ended_date] = ended_date
        else
          # Clear membership_ended_date if there's a recent payment
          updates[:membership_ended_date] = nil if user.membership_ended_date.present?
        end
      end

      if updates.any?
        user.update_columns(updates)
        users_updated += 1
        if updates[:membership_start_date] || updates[:membership_ended_date]
          start_str = updates[:membership_start_date] ? updates[:membership_start_date].to_s : (user.membership_start_date&.to_s || 'nil')
          end_str = updates[:membership_ended_date] ? updates[:membership_ended_date].to_s : (updates.key?(:membership_ended_date) ? 'cleared' : (user.membership_ended_date&.to_s || 'nil'))
          puts "  #{user.display_name}: start=#{start_str}, ended=#{end_str}"
        end
      else
        users_skipped += 1
      end
    end

    puts "  Users updated: #{users_updated}"
    puts "  Users skipped (no changes): #{users_skipped}"
  end

  desc "Show payment linking statistics without making changes"
  task link_stats: :environment do
    puts "=" * 60
    puts "Payment Linking Statistics"
    puts "=" * 60

    # PayPal stats
    puts "\nPayPal Payments:"
    total_paypal = PaypalPayment.count
    linked_paypal = PaypalPayment.where.not(user_id: nil).count
    unlinked_with_payer_id = PaypalPayment.where(user_id: nil).where.not(payer_id: [nil, '']).count
    unlinked_no_payer_id = PaypalPayment.where(user_id: nil, payer_id: [nil, '']).count
    dont_link_paypal = PaypalPayment.where(dont_link: true).count

    # Count how many unlinked could be matched
    paypal_user_map = User.where.not(paypal_account_id: [nil, ''])
                          .pluck(:paypal_account_id, :id)
                          .to_h
    matchable_paypal = PaypalPayment.where(user_id: nil)
                                    .where.not(payer_id: [nil, ''])
                                    .where(payer_id: paypal_user_map.keys)
                                    .count

    puts "  Total: #{total_paypal}"
    puts "  Linked: #{linked_paypal}"
    puts "  Don't Link: #{dont_link_paypal}"
    puts "  Unlinked (with payer ID): #{unlinked_with_payer_id}"
    puts "  Unlinked (no payer ID): #{unlinked_no_payer_id}"
    puts "  Could be linked now: #{matchable_paypal}"

    # Recharge stats
    puts "\nRecharge Payments:"
    total_recharge = RechargePayment.count
    linked_recharge = RechargePayment.where.not(user_id: nil).count
    unlinked_with_customer_id = RechargePayment.where(user_id: nil).where.not(customer_id: [nil, '']).count
    unlinked_no_customer_id = RechargePayment.where(user_id: nil, customer_id: [nil, '']).count
    dont_link_recharge = RechargePayment.where(dont_link: true).count

    # Count how many unlinked could be matched
    recharge_user_map = User.where.not(recharge_customer_id: [nil, ''])
                            .pluck(:recharge_customer_id, :id)
                            .to_h
    matchable_recharge = RechargePayment.where(user_id: nil)
                                        .where.not(customer_id: [nil, ''])
                                        .where(customer_id: recharge_user_map.keys)
                                        .count

    puts "  Total: #{total_recharge}"
    puts "  Linked: #{linked_recharge}"
    puts "  Don't Link: #{dont_link_recharge}"
    puts "  Unlinked (with customer ID): #{unlinked_with_customer_id}"
    puts "  Unlinked (no customer ID): #{unlinked_no_customer_id}"
    puts "  Could be linked now: #{matchable_recharge}"

    puts "\n" + "=" * 60
    puts "Run 'rails payments:link' to link #{matchable_paypal + matchable_recharge} payments"
  end
end
