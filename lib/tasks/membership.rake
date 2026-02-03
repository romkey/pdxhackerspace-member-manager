# Helper module for membership rake tasks
module MembershipTaskHelpers
  def self.find_matching_plan(plans, amount)
    return nil if amount.blank? || amount <= 0

    # Try exact match first
    exact_match = plans.find { |p| p.cost == amount }
    return exact_match if exact_match

    # Try matching within a small tolerance (for rounding differences)
    tolerance = 0.50
    close_match = plans.find { |p| (p.cost - amount).abs <= tolerance }
    return close_match if close_match

    nil
  end

  # Calculate the cutoff date based on a plan's billing frequency
  # Returns the date before which a payment would be considered lapsed
  def self.cutoff_for_plan(plan)
    return 1.month.ago unless plan # Default to monthly if no plan

    case plan.billing_frequency
    when 'monthly'
      1.month.ago
    when 'yearly'
      1.year.ago
    when 'one-time'
      # One-time payments never lapse (use a very old date)
      100.years.ago
    else
      1.month.ago # Default fallback
    end
  end

  # Human-readable description of the billing period
  def self.billing_period_description(plan)
    return '1 month (default)' unless plan

    case plan.billing_frequency
    when 'monthly' then '1 month'
    when 'yearly' then '1 year'
    when 'one-time' then 'never (one-time)'
    else '1 month (default)'
    end
  end
end

namespace :membership do
  desc "Reset and recalculate membership status based on sheet entries and recent payments"
  task recalculate_status: :environment do
    puts "Membership Status Recalculation"
    puts "=" * 50
    puts "Cutoff dates are based on each user's membership plan billing frequency:"
    puts "  - Monthly plans: payment within last 1 month"
    puts "  - Yearly plans: payment within last 1 year"
    puts "  - One-time plans: never lapse"
    puts "  - No plan match: defaults to 1 month"
    puts ""

    # Load membership plans for matching
    membership_plans = MembershipPlan.all.to_a
    puts "Loaded #{membership_plans.count} membership plans for matching:"
    membership_plans.each do |plan|
      puts "  - #{plan.name}: $#{format('%.2f', plan.cost)} (#{plan.billing_frequency})"
    end
    puts ""

    # Step 1: Reset everyone
    puts "Step 1: Resetting all users..."
    User.update_all(
      membership_status: 'unknown',
      dues_status: 'unknown',
      active: false,
      membership_plan_id: nil
    )
    puts "  Reset #{User.count} users to unknown/inactive"
    puts ""

    # Step 2: Set sponsored users from sheet entries
    puts "Step 2: Setting sponsored users from sheet entries..."
    sponsored_count = 0

    SheetEntry.where('LOWER(status) LIKE ?', '%sponsored%').find_each do |sheet_entry|
      user = sheet_entry.user
      next unless user

      user.update_columns(
        membership_status: 'sponsored',
        payment_type: 'sponsored',
        dues_status: 'current', # Sponsored members are always current
        active: true,
        updated_at: Time.current
      )
      sponsored_count += 1
      puts "  Sponsored: #{user.display_name}"
    end
    puts "  Set #{sponsored_count} users as sponsored"
    puts ""

    # Step 3: Process payment history for each user
    puts "Step 3: Processing payment history..."
    paying_count = 0
    lapsed_count = 0
    plan_matched_count = 0

    User.find_each do |user|
      # Skip if already sponsored (don't downgrade)
      next if user.membership_status == 'sponsored'

      # Collect all payments (PayPal and Recharge) with normalized structure
      all_payments = []

      user.paypal_payments.each do |p|
        next unless p.transaction_time.present?
        all_payments << {
          time: p.transaction_time,
          amount: p.amount,
          type: 'paypal'
        }
      end

      user.recharge_payments.each do |p|
        next unless p.processed_at.present?
        all_payments << {
          time: p.processed_at,
          amount: p.amount,
          type: 'recharge'
        }
      end

      next if all_payments.empty?

      # Sort oldest to newest
      all_payments.sort_by! { |p| p[:time] }
      latest_payment = all_payments.last

      # First, match membership plan based on latest payment amount
      matched_plan = nil
      if latest_payment[:amount].present?
        matched_plan = MembershipTaskHelpers.find_matching_plan(membership_plans, latest_payment[:amount])
        if matched_plan
          user.update_columns(
            membership_plan_id: matched_plan.id,
            updated_at: Time.current
          )
          plan_matched_count += 1
        end
      end

      # Calculate cutoff based on matched plan's billing frequency
      cutoff_date = MembershipTaskHelpers.cutoff_for_plan(matched_plan)

      # Process payments to determine current status
      # We check if the latest payment is within the plan's billing period
      if latest_payment[:time] >= cutoff_date
        # Recent payment - set as current and active
        user.update_columns(
          membership_status: 'paying',
          dues_status: 'current',
          payment_type: latest_payment[:type],
          active: true,
          updated_at: Time.current
        )
        paying_count += 1
        plan_info = matched_plan ? " [#{matched_plan.name}, #{MembershipTaskHelpers.billing_period_description(matched_plan)}]" : " [no plan, 1 month default]"
        puts "  Paying: #{user.display_name} (#{latest_payment[:type]})#{plan_info}"
      else
        # Payment is older than the billing period - lapsed
        user.update_columns(
          dues_status: 'lapsed',
          payment_type: latest_payment[:type],
          updated_at: Time.current
        )
        lapsed_count += 1
        plan_info = matched_plan ? " [#{matched_plan.name}, #{MembershipTaskHelpers.billing_period_description(matched_plan)}]" : " [no plan, 1 month default]"
        puts "  Lapsed: #{user.display_name} (last payment: #{latest_payment[:time].to_date})#{plan_info}"
      end
    end

    puts ""
    puts "  Set #{paying_count} users as paying"
    puts "  Set #{lapsed_count} users as lapsed"
    puts "  Matched #{plan_matched_count} users to membership plans"
    puts ""

    # Summary
    puts "=" * 50
    puts "Summary:"
    puts "  Total users: #{User.count}"
    puts "  Sponsored: #{User.where(membership_status: 'sponsored').count}"
    puts "  Paying: #{User.where(membership_status: 'paying').count}"
    puts "  Lapsed: #{User.where(dues_status: 'lapsed').count}"
    puts "  Active: #{User.where(active: true).count}"
    puts "  Inactive: #{User.where(active: false).count}"
    puts "  With membership plan: #{User.where.not(membership_plan_id: nil).count}"
    puts ""
    puts "Done!"
  end

  desc "Preview membership status recalculation (dry run)"
  task preview_recalculate: :environment do
    membership_plans = MembershipPlan.all.to_a

    puts "DRY RUN - No changes will be made"
    puts "=" * 50
    puts "Cutoff dates are based on each user's membership plan billing frequency:"
    puts "  - Monthly plans: payment within last 1 month"
    puts "  - Yearly plans: payment within last 1 year"
    puts "  - One-time plans: never lapse"
    puts "  - No plan match: defaults to 1 month"
    puts ""
    puts "Membership plans:"
    membership_plans.each do |plan|
      puts "  - #{plan.name}: $#{format('%.2f', plan.cost)} (#{plan.billing_frequency})"
    end
    puts ""

    would_sponsor = []
    would_pay = []
    would_lapsed = []
    would_inactive = []

    # Check sponsored from sheet entries
    SheetEntry.where('LOWER(status) LIKE ?', '%sponsored%').find_each do |sheet_entry|
      user = sheet_entry.user
      next unless user

      would_sponsor << user
    end

    # Check users with payments
    User.find_each do |user|
      next if would_sponsor.include?(user)

      all_payments = []
      user.paypal_payments.each do |p|
        next unless p.transaction_time.present?
        all_payments << { time: p.transaction_time, amount: p.amount, type: 'paypal' }
      end
      user.recharge_payments.each do |p|
        next unless p.processed_at.present?
        all_payments << { time: p.processed_at, amount: p.amount, type: 'recharge' }
      end

      if all_payments.empty?
        would_inactive << user
        next
      end

      all_payments.sort_by! { |p| p[:time] }
      latest_payment = all_payments.last

      # Match plan based on latest payment amount
      matched_plan = MembershipTaskHelpers.find_matching_plan(membership_plans, latest_payment[:amount])

      # Calculate cutoff based on matched plan's billing frequency
      cutoff_date = MembershipTaskHelpers.cutoff_for_plan(matched_plan)

      if latest_payment[:time] >= cutoff_date
        would_pay << {
          user: user,
          type: latest_payment[:type],
          amount: latest_payment[:amount],
          plan: matched_plan,
          last_payment: latest_payment[:time]
        }
      else
        would_lapsed << {
          user: user,
          plan: matched_plan,
          last_payment: latest_payment[:time]
        }
      end
    end

    puts "Would set as SPONSORED (#{would_sponsor.count}):"
    would_sponsor.each { |u| puts "  - #{u.display_name}" }
    puts ""

    puts "Would set as PAYING (#{would_pay.count}):"
    would_pay.first(20).each do |p|
      plan_info = p[:plan] ? "#{p[:plan].name} (#{p[:plan].billing_frequency})" : "no plan (1 month default)"
      puts "  - #{p[:user].display_name} (#{p[:type]}, $#{p[:amount]}) => #{plan_info}"
    end
    puts "  ... and #{would_pay.count - 20} more" if would_pay.count > 20
    puts ""

    puts "Would set as LAPSED (#{would_lapsed.count}):"
    would_lapsed.first(20).each do |l|
      plan_info = l[:plan] ? "#{l[:plan].name} (#{l[:plan].billing_frequency})" : "no plan (1 month default)"
      puts "  - #{l[:user].display_name} (last payment: #{l[:last_payment].to_date}) => #{plan_info}"
    end
    puts "  ... and #{would_lapsed.count - 20} more" if would_lapsed.count > 20
    puts ""

    puts "Would set as INACTIVE (#{would_inactive.count}):"
    would_inactive.first(20).each { |u| puts "  - #{u.display_name}" }
    puts "  ... and #{would_inactive.count - 20} more" if would_inactive.count > 20
    puts ""

    puts "=" * 50
    puts "Summary (if applied):"
    puts "  Sponsored: #{would_sponsor.count}"
    puts "  Paying: #{would_pay.count}"
    puts "  Lapsed: #{would_lapsed.count}"
    puts "  Inactive: #{would_inactive.count}"
    puts "  Would match to plan: #{would_pay.count { |p| p[:plan].present? }}"
    puts ""
    puts "Run 'rake membership:recalculate_status' to apply changes."
  end

  desc "Backfill membership_start_date from earliest PayPal payment after Dec 22, 2022"
  task backfill_start_dates: :environment do
    # Cutoff date: Dec 22, 2022
    cutoff_date = Date.new(2022, 12, 22)

    updated_count = 0
    skipped_count = 0
    no_payment_count = 0

    User.find_each do |user|
      # Skip if already has a membership_start_date
      if user.membership_start_date.present?
        skipped_count += 1
        next
      end

      # Find the earliest PayPal payment for this user after the cutoff date
      earliest_payment = user.paypal_payments
                             .where("transaction_time >= ?", cutoff_date)
                             .order(:transaction_time)
                             .first

      if earliest_payment&.transaction_time.present?
        start_date = earliest_payment.transaction_time.to_date
        user.update_column(:membership_start_date, start_date)
        updated_count += 1
        puts "Updated #{user.display_name}: #{start_date}"
      else
        no_payment_count += 1
      end
    end

    puts ""
    puts "=" * 50
    puts "Backfill complete!"
    puts "  Updated: #{updated_count} users"
    puts "  Skipped (already had date): #{skipped_count} users"
    puts "  No qualifying PayPal payments: #{no_payment_count} users"
  end

  desc "Preview membership_start_date backfill (dry run)"
  task preview_backfill: :environment do
    cutoff_date = Date.new(2022, 12, 22)

    would_update = []
    already_set = []
    no_payment = []

    User.find_each do |user|
      if user.membership_start_date.present?
        already_set << user
        next
      end

      earliest_payment = user.paypal_payments
                             .where("transaction_time >= ?", cutoff_date)
                             .order(:transaction_time)
                             .first

      if earliest_payment&.transaction_time.present?
        would_update << {
          user: user,
          date: earliest_payment.transaction_time.to_date,
          payment_id: earliest_payment.paypal_id
        }
      else
        no_payment << user
      end
    end

    puts "DRY RUN - No changes will be made"
    puts "=" * 50
    puts ""

    if would_update.any?
      puts "Would update #{would_update.count} users:"
      would_update.each do |entry|
        puts "  #{entry[:user].display_name} => #{entry[:date]} (from PayPal #{entry[:payment_id]})"
      end
      puts ""
    end

    puts "Already have membership_start_date: #{already_set.count} users"
    puts "No qualifying PayPal payments: #{no_payment.count} users"
    puts ""
    puts "Run 'rake membership:backfill_start_dates' to apply changes."
  end

  desc "Generate usernames for users without one (firstname + lastname, alphanumeric only)"
  task generate_usernames: :environment do
    puts "Username Generation"
    puts "=" * 50
    puts ""

    users_without_username = User.where(username: [nil, ''])
    puts "Found #{users_without_username.count} users without usernames"
    puts ""

    updated_count = 0
    skipped_count = 0
    conflict_count = 0

    users_without_username.find_each do |user|
      if user.full_name.blank?
        puts "  Skipped: User ##{user.id} (no full_name)"
        skipped_count += 1
        next
      end

      # Generate base username: lowercase, alphanumeric only
      base_username = user.full_name.downcase
                                    .gsub(/[^a-z0-9]/, '') # Remove everything except letters and numbers
                                    .truncate(50, omission: '')

      if base_username.blank?
        puts "  Skipped: #{user.full_name} (no valid characters)"
        skipped_count += 1
        next
      end

      # Find a unique username
      candidate = base_username
      counter = 1

      while User.where(username: candidate).where.not(id: user.id).exists?
        candidate = "#{base_username}#{counter}"
        counter += 1
        if counter > 100
          puts "  Conflict: #{user.full_name} - too many conflicts for '#{base_username}'"
          conflict_count += 1
          candidate = nil
          break
        end
      end

      next unless candidate

      user.update_column(:username, candidate)
      updated_count += 1
      puts "  Set: #{user.full_name} => #{candidate}"
    end

    puts ""
    puts "=" * 50
    puts "Summary:"
    puts "  Updated: #{updated_count} users"
    puts "  Skipped (no name): #{skipped_count} users"
    puts "  Conflicts: #{conflict_count} users"
  end

  desc "Preview username generation (dry run)"
  task preview_usernames: :environment do
    puts "DRY RUN - No changes will be made"
    puts "=" * 50
    puts ""

    users_without_username = User.where(username: [nil, ''])
    puts "Found #{users_without_username.count} users without usernames"
    puts ""

    would_update = []
    would_skip = []
    would_conflict = []

    users_without_username.find_each do |user|
      if user.full_name.blank?
        would_skip << { user: user, reason: 'no full_name' }
        next
      end

      base_username = user.full_name.downcase
                                    .gsub(/[^a-z0-9]/, '')
                                    .truncate(50, omission: '')

      if base_username.blank?
        would_skip << { user: user, reason: 'no valid characters' }
        next
      end

      candidate = base_username
      counter = 1

      while User.where(username: candidate).where.not(id: user.id).exists? ||
            would_update.any? { |w| w[:username] == candidate }
        candidate = "#{base_username}#{counter}"
        counter += 1
        if counter > 100
          would_conflict << { user: user, base: base_username }
          candidate = nil
          break
        end
      end

      next unless candidate

      would_update << { user: user, username: candidate }
    end

    if would_update.any?
      puts "Would set usernames for #{would_update.count} users:"
      would_update.each { |w| puts "  #{w[:user].full_name} => #{w[:username]}" }
      puts ""
    end

    if would_skip.any?
      puts "Would skip #{would_skip.count} users:"
      would_skip.each { |w| puts "  User ##{w[:user].id}: #{w[:reason]}" }
      puts ""
    end

    if would_conflict.any?
      puts "Would have conflicts for #{would_conflict.count} users:"
      would_conflict.each { |w| puts "  #{w[:user].full_name} (#{w[:base]})" }
      puts ""
    end

    puts "Run 'rake membership:generate_usernames' to apply changes."
  end
end
