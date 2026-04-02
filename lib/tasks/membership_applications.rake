# frozen_string_literal: true

namespace :membership_applications do
  desc 'Link membership applications to users when emails match (primary or extra_emails), case-insensitive'
  task link_by_email: :environment do
    linked = 0
    skipped = 0

    MembershipApplication.where(user_id: nil).find_each do |app|
      email = app.email.to_s.strip.downcase
      if email.blank?
        skipped += 1
        next
      end

      user = User.where('LOWER(TRIM(email)) = ?', email).first
      user ||= User.where(
        'EXISTS (SELECT 1 FROM unnest(extra_emails) AS e WHERE LOWER(TRIM(e)) = ?)',
        email
      ).first

      if user
        app.update!(user: user)
        linked += 1
        puts "Linked application #{app.id} (#{app.email}) → user #{user.id} (#{user.display_name})"
      else
        skipped += 1
      end
    end

    puts "Done. Linked #{linked} application(s); #{skipped} skipped (no match or blank email)."
  end
end
