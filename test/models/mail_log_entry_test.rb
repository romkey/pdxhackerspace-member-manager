# frozen_string_literal: true

require 'test_helper'

class MailLogEntryTest < ActiveSupport::TestCase
  test 'log_direct_delivery! creates a sent entry without queued mail' do
    entry = MailLogEntry.log_direct_delivery!(
      to: 'admin@example.com',
      subject: 'Hello',
      mailer_class: 'MemberMailer',
      mailer_action: 'admin_new_application'
    )

    assert_nil entry.queued_mail_id
    assert_equal 'sent', entry.event
    assert_equal 'admin@example.com', entry.delivery_to
    assert_equal 'Hello', entry.delivery_subject
    assert_equal 'MemberMailer', entry.delivery_mailer
    assert_equal 'admin_new_application', entry.delivery_action
  end

  test 'log_direct_delivery! requires to and subject' do
    assert_raises(ActiveRecord::RecordInvalid) do
      MailLogEntry.log_direct_delivery!(
        to: '',
        subject: 'Subj',
        mailer_class: 'X',
        mailer_action: 'y'
      )
    end
  end
end
