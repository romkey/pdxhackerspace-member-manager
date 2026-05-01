# frozen_string_literal: true

require 'test_helper'

module MembershipApplications
  class NotifyDirectorsOfStaleApplicationsTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      ActionMailer::Base.deliveries.clear
      EmailTemplate.where(key: 'staff_application_nag').delete_all
      EmailTemplate.create!(
        key: 'staff_application_nag',
        name: 'Staff Application Nag',
        subject: 'Nag {{member_name}} after {{application_age_days}} days',
        body_html: '<p>{{application_url}}</p><p>{{submitted_at}}</p>',
        body_text: "Open: {{application_url}}\nSubmitted: {{submitted_at}}",
        enabled: true
      )
    end

    test 'emails executive application reviewers for applications pending after a week' do
      now = Time.zone.local(2026, 5, 1, 9, 0, 0)
      application = stale_application(now: now, email: 'stale-review@example.com')
      train_staff(users(:one), MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      train_staff(users(:two), MembershipApplication::ASSOCIATE_EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)

      travel_to now do
        assert_difference 'ActionMailer::Base.deliveries.size', 2 do
          perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
            NotifyDirectorsOfStaleApplications.call(now: now)
          end
        end
      end

      assert_equal now, application.reload.application_nag_sent_at
      assert_equal [users(:one).email, users(:two).email].sort,
                   ActionMailer::Base.deliveries.flat_map(&:to).sort

      mail = ActionMailer::Base.deliveries.first
      assert_equal 'Nag Applicant after 8 days', mail.subject
      assert_includes mail.text_part.body.decoded, "/membership_applications/#{application.id}"
      assert_includes mail.text_part.body.decoded, 'April 23, 2026'
    end

    test 'does not email applications that are not stale and pending' do
      now = Time.zone.local(2026, 5, 1, 9, 0, 0)
      train_staff(users(:one), MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      stale_application(now: now, email: 'already-approved@example.com', status: 'approved')
      stale_application(now: now, email: 'already-rejected@example.com', status: 'rejected')
      stale_application(now: now, email: 'recently-nagged@example.com', application_nag_sent_at: now - 2.days)
      MembershipApplication.create!(
        email: 'too-new@example.com',
        status: 'submitted',
        submitted_at: now - 6.days,
        created_at: now - 6.days
      )

      travel_to now do
        assert_no_difference 'ActionMailer::Base.deliveries.size' do
          perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
            NotifyDirectorsOfStaleApplications.call(now: now)
          end
        end
      end
    end

    test 'emails applications again when the previous nag is at least three days old' do
      now = Time.zone.local(2026, 5, 1, 9, 0, 0)
      application = stale_application(
        now: now,
        email: 'repeat-due@example.com',
        application_nag_sent_at: now - 3.days
      )
      train_staff(users(:one), MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)

      travel_to now do
        assert_difference 'ActionMailer::Base.deliveries.size', 1 do
          perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
            NotifyDirectorsOfStaleApplications.call(now: now)
          end
        end
      end

      assert_equal now, application.reload.application_nag_sent_at
    end

    test 'does not repeat nag before three days have passed' do
      now = Time.zone.local(2026, 5, 1, 9, 0, 0)
      application = stale_application(
        now: now,
        email: 'repeat-not-due@example.com',
        application_nag_sent_at: now - 2.days
      )
      train_staff(users(:one), MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)

      travel_to now do
        assert_no_difference 'ActionMailer::Base.deliveries.size' do
          perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
            NotifyDirectorsOfStaleApplications.call(now: now)
          end
        end
      end

      assert_equal now - 2.days, application.reload.application_nag_sent_at
    end

    test 'deduplicates reviewers and only marks sent when a recipient exists' do
      now = Time.zone.local(2026, 5, 1, 9, 0, 0)
      application = stale_application(now: now, email: 'dedupe@example.com')
      train_staff(users(:one), MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      train_staff(users(:one), MembershipApplication::ASSOCIATE_EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      staff_without_email = users(:no_email)
      train_staff(staff_without_email, MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)

      travel_to now do
        assert_difference 'ActionMailer::Base.deliveries.size', 1 do
          perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
            NotifyDirectorsOfStaleApplications.call(now: now)
          end
        end
      end

      assert_equal now, application.reload.application_nag_sent_at
      assert_equal [users(:one).email], ActionMailer::Base.deliveries.flat_map(&:to)
    end

    test 'leaves stale application unmarked when no director recipients exist' do
      now = Time.zone.local(2026, 5, 1, 9, 0, 0)
      application = stale_application(now: now, email: 'no-recipients@example.com')

      travel_to now do
        assert_no_difference 'ActionMailer::Base.deliveries.size' do
          perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
            NotifyDirectorsOfStaleApplications.call(now: now)
          end
        end
      end

      assert_nil application.reload.application_nag_sent_at
    end

    private

    def stale_application(now:, email:, status: 'submitted', application_nag_sent_at: nil)
      MembershipApplication.create!(
        email: email,
        status: status,
        submitted_at: now - 8.days,
        created_at: now - 8.days,
        application_nag_sent_at: application_nag_sent_at
      )
    end

    def train_staff(user, topic_name)
      topic = TrainingTopic.find_or_create_by!(name: topic_name)
      Training.create!(trainee: user, training_topic: topic, trained_at: Time.current)
    end
  end
end
