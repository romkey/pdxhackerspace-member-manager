require 'test_helper'

class UserTest < ActiveSupport::TestCase
  test 'ordered_by_display_name sorts by name then email' do
    ordered = User.ordered_by_display_name.map(&:display_name)

    # Verify the list is sorted case-insensitively
    assert_equal(ordered, ordered.sort_by(&:downcase))

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

  test 'by_name_or_alias matches single-word full_name exactly' do
    user = User.create!(
      authentik_id: 'single-word-test',
      email: 'singleword@example.com',
      full_name: 'Madonna',
      active: true
    )

    assert_equal user, User.by_name_or_alias('Madonna').first
    assert_equal user, User.by_name_or_alias('madonna').first
  end

  test 'by_name_or_alias matches single-word alias exactly' do
    user = users(:one)
    user.update_columns(aliases: ['Cher'], full_name: 'Example User One')

    assert_equal user, User.by_name_or_alias('Cher').first
  end

  test 'by_name_or_alias does not match first word of multi-word full_name' do
    user = users(:one)
    assert_equal 'Example User One', user.full_name

    assert_nil User.by_name_or_alias('Example').first
    assert_nil User.by_name_or_alias('One').first
  end

  test 'by_name_or_alias still matches multi-word full_name exactly' do
    user = users(:one)
    assert_equal user, User.by_name_or_alias('Example User One').first
  end
end
