require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'ordered_by_display_name sorts by name then email' do
    ordered = User.ordered_by_display_name.map(&:display_name)

    # Verify the list is sorted case-insensitively
    assert_equal ordered, ordered.sort_by { |name| name.downcase }

    # Verify all fixture users are included
    assert_includes ordered, 'Example User One'
    assert_includes ordered, 'Example User Two'
    assert_includes ordered, 'No Email User'
    assert_includes ordered, 'beta@example.com'
  end

  test 'allows users without email' do
    user = User.new(authentik_id: 'no-email', full_name: 'No Email')

    assert_predicate user, :valid?
  end

  test 'display_name falls back to authentik id' do
    user = User.new(authentik_id: 'fallback-id')

    assert_equal 'fallback-id', user.display_name
  end

  test 'with_attribute scope filters users by authentik attributes' do
    results = User.with_attribute(:department, 'Engineering')
    assert_equal ['user1@example.com'], results.pluck(:email)
  end
end
