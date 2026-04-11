# frozen_string_literal: true

require 'test_helper'

class MemberMailerTest < ActionMailer::TestCase
  test 'admin_new_application includes application URL in body when provided' do
    EmailTemplate.where(key: 'admin_new_application').update_all(enabled: false)

    applicant = users(:one)
    url = 'https://www.example.com/membership_applications/4242'

    email = nil
    assert_difference 'MailLogEntry.count', 1 do
      email = MemberMailer.admin_new_application(applicant, 'ops@example.com', application_url: url).deliver_now
    end

    entry = MailLogEntry.order(:created_at).last
    assert_nil entry.queued_mail_id
    assert_equal 'ops@example.com', entry.delivery_to
    assert entry.delivery_subject.present?

    assert_includes email.html_part.body.to_s, url
    text = email.text_part ? email.text_part.body.to_s : email.body.to_s
    assert_includes text, url
  end
end
