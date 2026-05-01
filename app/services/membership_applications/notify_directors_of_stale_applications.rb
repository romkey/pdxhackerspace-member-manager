# frozen_string_literal: true

module MembershipApplications
  # Reminds executive application reviewers when pending applications are older than one week.
  class NotifyDirectorsOfStaleApplications
    INITIAL_DELAY = 1.week
    REPEAT_DELAY = 3.days

    def self.call(now: Time.current)
      new(now: now).call
    end

    def initialize(now:)
      @now = now
    end

    def call
      MembershipApplication.awaiting_admin_nag(@now - INITIAL_DELAY, @now - REPEAT_DELAY).find_each do |application|
        notify_application(application)
      end
    end

    private

    def notify_application(application)
      application.with_lock do
        return unless naggable?(application)

        recipients = director_recipients
        return if recipients.empty?

        recipients.each do |staff|
          MemberMailer.staff_application_nag(application, staff.email.to_s.strip).deliver_later
        end
        application.update!(application_nag_sent_at: @now)
      end
    rescue StandardError => e
      Rails.logger.error(
        "[NotifyDirectorsOfStaleApplications] application_id=#{application&.id} #{e.class}: #{e.message}"
      )
    end

    def naggable?(application)
      application.pending? &&
        application_age_start(application) <= @now - INITIAL_DELAY &&
        next_nag_due?(application)
    end

    def application_age_start(application)
      application.submitted_at || application.created_at
    end

    def next_nag_due?(application)
      application.application_nag_sent_at.nil? ||
        application.application_nag_sent_at <= @now - REPEAT_DELAY
    end

    def director_recipients
      recipients = []
      DirectorRecipients.find_each { |staff| recipients << staff }
      recipients
    end
  end
end
