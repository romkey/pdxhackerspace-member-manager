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

    # Update user statuses (payment type, membership status, dues status)
    puts "\n" + "-" * 60
    puts "Updating user statuses..."
    status_updates = update_user_statuses

    # Set membership dates
    puts "\n" + "-" * 60
    puts "Setting membership dates..."
    update_membership_dates

    # Link membership plans based on PayPal transaction subjects
    puts "\n" + "-" * 60
    puts "Linking membership plans from PayPal transaction subjects..."
    plans_linked = link_membership_plans_from_paypal

    # Summary
    puts "\n" + "=" * 60
    puts "SUMMARY"
    puts "=" * 60
    puts "PayPal payments linked: #{paypal_updated}"
    puts "Recharge payments linked: #{recharge_updated}"
    puts "Total payments linked: #{paypal_updated + recharge_updated}"
    puts "User statuses updated: #{status_updates}"
    puts "Membership plans linked: #{plans_linked[:primary]} primary, #{plans_linked[:supplementary]} supplementary"
    puts "\nDone!"
  end

  # Helper method to update user payment type, membership status, and dues status
  def update_user_statuses
    users_updated = 0
    cutoff_date = 32.days.ago.to_date

    # Find all users with linked payments
    user_ids_with_payments = (
      PaypalPayment.where.not(user_id: nil).select(:user_id).distinct.pluck(:user_id) +
      RechargePayment.where.not(user_id: nil).select(:user_id).distinct.pluck(:user_id)
    ).uniq

    User.where(id: user_ids_with_payments).find_each do |user|
      updates = {}

      # Find most recent payment from each source
      latest_paypal = user.paypal_payments.maximum(:transaction_time)
      latest_recharge = user.recharge_payments.maximum(:processed_at)

      # Determine payment type based on which has more recent payment
      if latest_paypal.present? && latest_recharge.present?
        updates[:payment_type] = latest_paypal > latest_recharge ? 'paypal' : 'recharge'
      elsif latest_paypal.present?
        updates[:payment_type] = 'paypal'
      elsif latest_recharge.present?
        updates[:payment_type] = 'recharge'
      end

      # Find the absolute most recent payment date
      most_recent = [latest_paypal, latest_recharge].compact.max

      if most_recent.present?
        most_recent_date = most_recent.to_date

        # If payment is within 32 days, user should be active with current dues
        if most_recent_date >= cutoff_date
          updates[:active] = true unless user.active?
          updates[:membership_status] = 'paying' unless user.membership_status == 'paying'
          updates[:dues_status] = 'current' unless user.dues_status == 'current'
        else
          # Payment is older than 32 days - mark as lapsed if currently showing as current
          if user.dues_status == 'current'
            updates[:dues_status] = 'lapsed'
          end
        end
      end

      # Only update if there are changes
      if updates.any?
        # Remove no-op updates
        updates.delete(:payment_type) if updates[:payment_type] == user.payment_type
        updates.delete(:active) if updates[:active] == user.active?
        updates.delete(:membership_status) if updates[:membership_status] == user.membership_status
        updates.delete(:dues_status) if updates[:dues_status] == user.dues_status

        if updates.any?
          user.update_columns(updates)
          users_updated += 1
          puts "  #{user.display_name}: #{updates.map { |k, v| "#{k}=#{v}" }.join(', ')}"
        end
      end
    end

    puts "  Users updated: #{users_updated}"
    users_updated
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

  # Helper method to link membership plans based on PayPal transaction subjects
  def link_membership_plans_from_paypal
    primary_linked = 0
    supplementary_linked = 0

    # Get all plans that have transaction subjects defined
    plans_with_subjects = MembershipPlan.with_transaction_subject.to_a

    if plans_with_subjects.empty?
      puts "  No membership plans with PayPal transaction subjects configured"
      return { primary: 0, supplementary: 0 }
    end

    puts "  Found #{plans_with_subjects.size} plans with transaction subjects:"
    plans_with_subjects.each do |plan|
      puts "    - #{plan.name} (#{plan.plan_type}): '#{plan.paypal_transaction_subject}'"
    end

    # Process each user with PayPal payments
    User.joins(:paypal_payments).distinct.find_each do |user|
      # Find all unique plans that match this user's PayPal payments
      matched_plans = Set.new

      user.paypal_payments.each do |payment|
        next unless payment.raw_attributes.present?

        raw_json = payment.raw_attributes.to_s

        plans_with_subjects.each do |plan|
          if raw_json.include?(plan.paypal_transaction_subject)
            matched_plans << plan
          end
        end
      end

      next if matched_plans.empty?

      # Process matched plans
      matched_plans.each do |plan|
        if plan.primary?
          # Assign primary plan if user doesn't have one
          if user.membership_plan_id.nil?
            user.update_column(:membership_plan_id, plan.id)
            primary_linked += 1
            puts "  #{user.display_name}: Primary plan set to '#{plan.name}'"
          elsif user.membership_plan_id != plan.id
            # User already has a different primary plan - skip but note
            puts "  #{user.display_name}: Already has primary plan '#{user.membership_plan.name}', skipping '#{plan.name}'"
          end
        else
          # Add supplementary plan if not already assigned
          unless user.has_plan?(plan)
            if user.add_supplementary_plan(plan)
              supplementary_linked += 1
              puts "  #{user.display_name}: Added supplementary plan '#{plan.name}'"
            end
          end
        end
      end
    end

    puts "  Primary plans linked: #{primary_linked}"
    puts "  Supplementary plans linked: #{supplementary_linked}"

    { primary: primary_linked, supplementary: supplementary_linked }
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

    # Membership plan stats
    puts "\nMembership Plans (with transaction subjects):"
    plans_with_subjects = MembershipPlan.with_transaction_subject.to_a
    puts "  Configured plans: #{plans_with_subjects.size}"
    plans_with_subjects.each do |plan|
      puts "    - #{plan.name} (#{plan.plan_type}): '#{plan.paypal_transaction_subject}'"
    end

    if plans_with_subjects.any?
      # Count users without primary plans who could get one
      users_without_primary = User.where(membership_plan_id: nil).count
      puts "  Users without primary plan: #{users_without_primary}"
    end

    puts "\n" + "=" * 60
    puts "Run 'rails payments:link' to link #{matchable_paypal + matchable_recharge} payments"
  end
end
