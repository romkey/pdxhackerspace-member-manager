# frozen_string_literal: true

require 'test_helper'

class MembershipApplicationsLinkByEmailTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks
    @task = Rake::Task['membership_applications:link_by_email']
    @task.reenable
  end

  test 'links unlinked applications when email matches user primary email' do
    member = users(:one)
    app = MembershipApplication.create!(
      email: member.email.upcase,
      status: 'approved',
      submitted_at: 1.day.ago,
      user: nil
    )

    @task.invoke

    assert_equal member.id, app.reload.user_id
  end

  test 'links when email matches extra_emails only' do
    member = users(:one)
    member.update!(extra_emails: ['aliasapply@example.com'])

    app = MembershipApplication.create!(
      email: 'aliasapply@example.com',
      status: 'submitted',
      submitted_at: Time.current,
      user: nil
    )

    @task.invoke

    assert_equal member.id, app.reload.user_id
  end
end
