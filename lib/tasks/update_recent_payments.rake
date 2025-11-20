namespace :users do
  desc "Update users with recent payments (within 32 days) to be active and set membership_status to basic if unknown"
  task update_recent_payments: :environment do
    cutoff_date = 32.days.ago.to_date
    updated_count = 0

    User.where.not(last_payment_date: nil)
        .where('last_payment_date >= ?', cutoff_date)
        .find_each do |user|
      updates = {}
      updates[:active] = true unless user.active?
      updates[:membership_status] = 'basic' if user.membership_status == 'unknown'

      if updates.any?
        user.update!(updates)
        updated_count += 1
        puts "Updated #{user.display_name}: #{updates.inspect}"
      end
    end

    puts "\nTotal users updated: #{updated_count}"
  end
end

