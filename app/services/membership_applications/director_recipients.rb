# frozen_string_literal: true

module MembershipApplications
  # Finds staff members trained for executive application review notifications.
  class DirectorRecipients
    def self.find_each(&)
      new.find_each(&)
    end

    def find_each
      topic_ids = TrainingTopic
                  .where(name: MembershipApplication::STAFF_APPLICATION_ALERT_TRAINING_TOPIC_NAMES)
                  .pluck(:id)
      return if topic_ids.empty?

      trainee_ids = Training.where(training_topic_id: topic_ids).distinct.select(:trainee_id)
      User.where(id: trainee_ids).find_each do |staff|
        next if staff.email.to_s.strip.blank?

        yield staff
      end
    end
  end
end
