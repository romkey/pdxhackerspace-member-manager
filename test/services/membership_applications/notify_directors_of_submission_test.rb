# frozen_string_literal: true

require 'test_helper'

module MembershipApplications
  class NotifyDirectorsOfSubmissionTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      @app = MembershipApplication.create!(email: 'notify-directors@example.com', status: 'submitted')
    end

    test 'sends one deliver_later mail per trained staff with email' do
      ed = TrainingTopic.create!(name: MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      aed = TrainingTopic.create!(name: MembershipApplication::ASSISTANT_EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      u1 = users(:one)
      u2 = users(:two)
      Training.create!(trainee: u1, training_topic: ed, trained_at: Time.current)
      Training.create!(trainee: u2, training_topic: aed, trained_at: Time.current)

      assert_difference 'ActionMailer::Base.deliveries.size', 2 do
        perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
          NotifyDirectorsOfSubmission.call(@app)
        end
      end

      ActionMailer::Base.deliveries.each do |mail|
        assert_match(/needs review/i, mail.subject)
      end
    end

    test 'deduplicates when one user holds both trainings' do
      ed = TrainingTopic.create!(name: MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      aed = TrainingTopic.create!(name: MembershipApplication::ASSISTANT_EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      u1 = users(:one)
      Training.create!(trainee: u1, training_topic: ed, trained_at: Time.current)
      Training.create!(trainee: u1, training_topic: aed, trained_at: Time.current)

      assert_difference 'ActionMailer::Base.deliveries.size', 1 do
        perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
          NotifyDirectorsOfSubmission.call(@app)
        end
      end
    end

    test 'no mail when no matching training topics exist' do
      TrainingTopic.where(name: MembershipApplication::STAFF_APPLICATION_ALERT_TRAINING_TOPIC_NAMES).delete_all

      assert_no_difference 'ActionMailer::Base.deliveries.size' do
        perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
          NotifyDirectorsOfSubmission.call(@app)
        end
      end
    end

    test 'no mail when topics exist but nobody is trained' do
      TrainingTopic.create!(name: MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)

      assert_no_difference 'ActionMailer::Base.deliveries.size' do
        perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
          NotifyDirectorsOfSubmission.call(@app)
        end
      end
    end

    test 'skips staff with blank email' do
      topic = TrainingTopic.create!(name: MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      staff = users(:one)
      staff.update_column(:email, '')
      Training.create!(trainee: staff, training_topic: topic, trained_at: Time.current)

      assert_no_difference 'ActionMailer::Base.deliveries.size' do
        perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
          NotifyDirectorsOfSubmission.call(@app)
        end
      end
    end
  end
end
