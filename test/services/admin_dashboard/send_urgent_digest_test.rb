# frozen_string_literal: true

require 'test_helper'

module AdminDashboard
  class SendUrgentDigestTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      ActionMailer::Base.deliveries.clear
      disable_authentik_urgency
      AccessController.delete_all
      PaymentProcessor.delete_all
      Printer.delete_all
      EmailTemplate.where(key: 'admin_dashboard_urgent_digest').delete_all
      EmailTemplate.create!(
        key: 'admin_dashboard_urgent_digest',
        name: 'Admin Dashboard Urgent Digest',
        subject: 'Urgent dashboard: {{urgent_item_count}}',
        body_html: '<h1>{{urgent_item_count}}</h1>{{urgent_items_html}}<p>{{dashboard_url}}</p>',
        body_text: "{{urgent_item_count}}\n{{urgent_items_text}}\n{{dashboard_url}}",
        enabled: true
      )
    end

    test 'emails executive directors when global urgent dashboard items exist' do
      staff = users(:one)
      train_staff(staff, MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      AccessController.create!(
        name: 'Front Door',
        hostname: 'front-door.local',
        ping_status: 'failed',
        sync_status: 'success',
        backup_status: 'success'
      )

      assert_difference 'ActionMailer::Base.deliveries.size', 1 do
        perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
          SendUrgentDigest.call
        end
      end

      mail = ActionMailer::Base.deliveries.last
      assert_equal [staff.email], mail.to
      assert_equal 'Urgent dashboard: 1', mail.subject
      assert_includes mail.text_part.body.decoded, '1 access controller issue'
      assert_includes mail.text_part.body.decoded, '1 offline'
      assert_includes mail.text_part.body.decoded, '/access_controllers'
    end

    test 'queues urgent digest emails through Action Mailer before delivery' do
      staff = users(:one)
      train_staff(staff, MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      AccessController.create!(
        name: 'Back Door',
        hostname: 'back-door.local',
        ping_status: 'failed',
        sync_status: 'success',
        backup_status: 'success'
      )

      assert_enqueued_jobs 1, only: ActionMailer::MailDeliveryJob do
        SendUrgentDigest.call
      end
    end

    test 'uses each director unread messages as recipient-specific urgent items' do
      staff_with_message = users(:one)
      staff_without_message = users(:two)
      train_staff(staff_with_message, MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      train_staff(staff_without_message, MembershipApplication::ASSOCIATE_EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)
      Message.create!(
        sender: staff_without_message,
        recipient: staff_with_message,
        subject: 'Please review this',
        body: 'Dashboard urgent digest should include this unread message.'
      )

      assert_difference 'ActionMailer::Base.deliveries.size', 1 do
        perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
          SendUrgentDigest.call
        end
      end

      mail = ActionMailer::Base.deliveries.last
      assert_equal [staff_with_message.email], mail.to
      assert_includes mail.text_part.body.decoded, '1 unread message'
      assert_includes mail.text_part.body.decoded, '/messages?folder=unread'
    end

    test 'does not email directors when there are no urgent dashboard items' do
      train_staff(users(:one), MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME)

      assert_no_difference 'ActionMailer::Base.deliveries.size' do
        perform_enqueued_jobs only: ActionMailer::MailDeliveryJob do
          SendUrgentDigest.call
        end
      end
    end

    private

    def disable_authentik_urgency
      MemberSource.find_by(key: 'authentik')&.update!(enabled: false, sync_status: 'healthy')
    end

    def train_staff(user, topic_name)
      topic = TrainingTopic.find_or_create_by!(name: topic_name)
      Training.create!(trainee: user, training_topic: topic, trained_at: Time.current)
    end
  end
end
