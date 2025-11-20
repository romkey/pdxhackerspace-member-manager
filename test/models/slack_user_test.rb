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
end
