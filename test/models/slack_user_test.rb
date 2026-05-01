require 'test_helper'

class SlackUserTest < ActiveSupport::TestCase
  test 'display name falls back through fields' do
    user = SlackUser.new(slack_id: 'U123', display_name: '', real_name: '', username: 'tester')
    assert_equal 'tester', user.display_name
  end

  test 'with_attribute scope filters on json column' do
    slack_users(:with_dept)
    slack_users(:with_other_dept)

    results = SlackUser.with_attribute(:department, 'IT')
    assert_equal ['with_dept@example.com'], results.pluck(:email)
  end

  test 'active scope excludes inactive and deactivated accounts' do
    recent = SlackUser.create!(slack_id: 'URECENT', last_active_at: 1.month.ago)
    old = SlackUser.create!(slack_id: 'UOLD', last_active_at: 2.years.ago)
    unknown = SlackUser.create!(slack_id: 'UUNKNOWN', last_active_at: nil)
    deactivated = SlackUser.create!(slack_id: 'UDEACTIVATED', deleted: true, last_active_at: 1.month.ago)

    assert_includes SlackUser.active, recent
    assert_not_includes SlackUser.active, old
    assert_not_includes SlackUser.active, unknown
    assert_not_includes SlackUser.active, deactivated
  end

  test 'inactive scope includes accounts with no or old activity' do
    recent = SlackUser.create!(slack_id: 'URECENT2', last_active_at: 1.month.ago)
    old = SlackUser.create!(slack_id: 'UOLD2', last_active_at: 2.years.ago)
    unknown = SlackUser.create!(slack_id: 'UUNKNOWN2', last_active_at: nil)

    assert_not_includes SlackUser.inactive, recent
    assert_includes SlackUser.inactive, old
    assert_includes SlackUser.inactive, unknown
  end
end
