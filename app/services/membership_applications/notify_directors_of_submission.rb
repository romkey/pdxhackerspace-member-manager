# frozen_string_literal: true

module MembershipApplications
  # Sends an immediate (non-queued) email to each user trained for executive application review
  # when a membership application is submitted.
  # No-op if those training topics do not exist or no trained recipients have an email.
  class NotifyDirectorsOfSubmission
    def self.call(application)
      new(application).call
    end

    def initialize(application)
      @application = application
    end

    def call
      DirectorRecipients.find_each do |staff|
        MemberMailer.staff_new_application(@application, staff.email.to_s.strip).deliver_later
      end
    rescue StandardError => e
      Rails.logger.error(
        "[NotifyDirectorsOfSubmission] application_id=#{@application&.id} #{e.class}: #{e.message}"
      )
    end
  end
end
