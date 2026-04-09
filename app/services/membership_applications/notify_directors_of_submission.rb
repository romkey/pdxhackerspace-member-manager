# frozen_string_literal: true

module MembershipApplications
  # Sends an immediate (non-queued) email to each user trained as Executive Director or
  # Assistant Executive Director when a membership application is submitted.
  # No-op if those training topics do not exist or no trained recipients have an email.
  class NotifyDirectorsOfSubmission
    def self.call(application)
      new(application).call
    end

    def initialize(application)
      @application = application
    end

    def call
      topic_ids = TrainingTopic
                  .where(name: MembershipApplication::STAFF_APPLICATION_ALERT_TRAINING_TOPIC_NAMES)
                  .pluck(:id)
      return if topic_ids.empty?

      trainee_ids = Training.where(training_topic_id: topic_ids).distinct.pluck(:trainee_id)
      return if trainee_ids.empty?

      User.where(id: trainee_ids).find_each do |staff|
        email = staff.email.to_s.strip
        next if email.blank?

        MemberMailer.staff_new_application(@application, email).deliver_later
      end
    rescue StandardError => e
      Rails.logger.error(
        "[NotifyDirectorsOfSubmission] application_id=#{@application&.id} #{e.class}: #{e.message}"
      )
    end
  end
end
