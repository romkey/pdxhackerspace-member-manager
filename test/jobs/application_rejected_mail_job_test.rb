# frozen_string_literal: true

require 'test_helper'

class ApplicationRejectedMailJobTest < ActiveJob::TestCase
  test 'creates pending queued mail for applicant email' do
    app = MembershipApplication.create!(email: 'job-reject-test@example.com', status: 'rejected')

    assert_difference -> { QueuedMail.count }, 1 do
      ApplicationRejectedMailJob.perform_now(app.id, 'Incomplete documentation')
    end

    mail = QueuedMail.order(:created_at).last
    assert_equal 'pending', mail.status
    assert_equal 'application_rejected', mail.mailer_action
    assert_equal 'job-reject-test@example.com', mail.to
    assert_includes mail.body_html, 'not able to approve'
    assert_includes mail.body_html, 'Incomplete documentation'
  end

  test 'discard when application is missing' do
    assert_nothing_raised do
      ApplicationRejectedMailJob.perform_now(-1, nil)
    end
  end

  test 'uses linked member email when present' do
    member = users(:member_with_local_account)
    app = MembershipApplication.create!(
      email: 'other@example.com',
      status: 'rejected',
      user: member
    )

    ApplicationRejectedMailJob.perform_now(app.id, nil)

    mail = QueuedMail.order(:created_at).last
    assert_equal member.email, mail.to
    assert_equal member, mail.recipient
  end
end
