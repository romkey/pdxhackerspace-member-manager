# frozen_string_literal: true

require 'test_helper'

class QueuedMailMailerTest < ActionMailer::TestCase
  test 'deliver_queued does not create a direct-only mail log entry' do
    qm = queued_mails(:pending_mail)
    assert_no_difference(-> { MailLogEntry.where(queued_mail_id: nil).count }) do
      QueuedMailMailer.deliver_queued(qm).deliver_now
    end
  end
end
