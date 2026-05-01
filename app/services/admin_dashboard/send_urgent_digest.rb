# frozen_string_literal: true

module AdminDashboard
  # Emails executive directors when their admin dashboard has urgent items.
  class SendUrgentDigest
    def self.call
      new.call
    end

    def call
      MembershipApplications::DirectorRecipients.find_each do |staff|
        items = UrgentItems.call(user: staff)
        next if items.empty?

        MemberMailer.admin_dashboard_urgent_digest(staff, items.map(&:to_h)).deliver_later
      end
    end
  end
end
