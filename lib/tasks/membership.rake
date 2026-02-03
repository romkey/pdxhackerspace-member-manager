namespace :membership do
  desc "Reset and recalculate membership status based on sheet entries and recent payments"
  task recalculate_status: :environment do
    cutoff_date = 1.month.ago

    puts "Membership Status Recalculation"
    puts "=" * 50
    puts "Cutoff date for recent payments: #{cutoff_date.to_date}"
    puts ""

    # Step 1: Reset everyone
    puts "Step 1: Resetting all users..."
    User.update_all(
      membership_status: 'unknown',
      dues_status: 'unknown',
      active: false
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

    # Step 3: Set users with recent payments as paying/active
    puts "Step 3: Checking recent payments..."
    paying_count = 0

    User.find_each do |user|
      # Skip if already sponsored (don't downgrade)
      next if user.membership_status == 'sponsored'

      # Check for recent PayPal payments
      recent_paypal = user.paypal_payments
                          .where('transaction_time >= ?', cutoff_date)
                          .exists?

      # Check for recent Recharge payments
      recent_recharge = user.recharge_payments
                            .where('processed_at >= ?', cutoff_date)
                            .exists?

      if recent_paypal || recent_recharge
        payment_type = recent_paypal ? 'paypal' : 'recharge'
        user.update_columns(
          membership_status: 'paying',
          dues_status: 'current',
          payment_type: payment_type,
          active: true,
          updated_at: Time.current
        )
        paying_count += 1
        puts "  Paying: #{user.display_name} (#{payment_type})"
      end
    end
    puts "  Set #{paying_count} users as paying"
    puts ""

    # Summary
    puts "=" * 50
    puts "Summary:"
    puts "  Total users: #{User.count}"
    puts "  Sponsored: #{User.where(membership_status: 'sponsored').count}"
    puts "  Paying: #{User.where(membership_status: 'paying').count}"
    puts "  Active: #{User.where(active: true).count}"
    puts "  Inactive: #{User.where(active: false).count}"
    puts ""
    puts "Done!"
  end

  desc "Preview membership status recalculation (dry run)"
  task preview_recalculate: :environment do
    cutoff_date = 1.month.ago

    puts "DRY RUN - No changes will be made"
    puts "=" * 50
    puts "Cutoff date for recent payments: #{cutoff_date.to_date}"
    puts ""

    would_sponsor = []
    would_pay = []
    would_inactive = []

    # Check sponsored from sheet entries
    SheetEntry.where('LOWER(status) LIKE ?', '%sponsored%').find_each do |sheet_entry|
      user = sheet_entry.user
      next unless user

      would_sponsor << user
    end

    # Check users with recent payments
    User.find_each do |user|
      # Skip if would be sponsored
      next if would_sponsor.include?(user)

      recent_paypal = user.paypal_payments
                          .where('transaction_time >= ?', cutoff_date)
                          .exists?

      recent_recharge = user.recharge_payments
                            .where('processed_at >= ?', cutoff_date)
                            .exists?

      if recent_paypal || recent_recharge
        would_pay << { user: user, type: recent_paypal ? 'paypal' : 'recharge' }
      else
        would_inactive << user
      end
    end

    puts "Would set as SPONSORED (#{would_sponsor.count}):"
    would_sponsor.each { |u| puts "  - #{u.display_name}" }
    puts ""

    puts "Would set as PAYING (#{would_pay.count}):"
    would_pay.first(20).each { |p| puts "  - #{p[:user].display_name} (#{p[:type]})" }
    puts "  ... and #{would_pay.count - 20} more" if would_pay.count > 20
    puts ""

    puts "Would set as INACTIVE (#{would_inactive.count}):"
    would_inactive.first(20).each { |u| puts "  - #{u.display_name}" }
    puts "  ... and #{would_inactive.count - 20} more" if would_inactive.count > 20
    puts ""

    puts "=" * 50
    puts "Summary (if applied):"
    puts "  Sponsored: #{would_sponsor.count}"
    puts "  Paying: #{would_pay.count}"
    puts "  Inactive: #{would_inactive.count}"
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
end
