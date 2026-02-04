namespace :payments do
  desc "Set user_id on PayPal and Recharge payments based on payer/customer ID matches"
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

    # Summary
    puts "\n" + "=" * 60
    puts "SUMMARY"
    puts "=" * 60
    puts "PayPal payments linked: #{paypal_updated}"
    puts "Recharge payments linked: #{recharge_updated}"
    puts "Total payments linked: #{paypal_updated + recharge_updated}"
    puts "\nDone!"
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
