require 'test_helper'

class UserGreetingTest < ActiveSupport::TestCase
  # greeting_option

  test 'greeting_option returns full_name when use_full_name_for_greeting is true' do
    user = User.new(use_full_name_for_greeting: true)
    assert_equal 'full_name', user.greeting_option
  end

  test 'greeting_option returns username when use_username_for_greeting is true' do
    user = User.new(use_full_name_for_greeting: false, use_username_for_greeting: true)
    assert_equal 'username', user.greeting_option
  end

  test 'greeting_option returns do_not_greet when do_not_greet is true' do
    user = User.new(use_full_name_for_greeting: false, use_username_for_greeting: false, do_not_greet: true)
    assert_equal 'do_not_greet', user.greeting_option
  end

  test 'greeting_option returns custom when none of the booleans are set' do
    user = User.new(
      use_full_name_for_greeting: false,
      use_username_for_greeting: false,
      do_not_greet: false,
      greeting_name: 'Sparky'
    )
    assert_equal 'custom', user.greeting_option
  end

  test 'greeting_option full_name takes precedence over username' do
    # The model's mutual-exclusivity callback should prevent both being set,
    # but greeting_option checks full_name first
    user = User.new(use_full_name_for_greeting: true, use_username_for_greeting: true)
    assert_equal 'full_name', user.greeting_option
  end

  # greeting_name auto-fill callbacks

  test 'auto_fill_greeting_name sets name from full_name when use_full_name_for_greeting' do
    user = users(:one)
    user.update!(use_full_name_for_greeting: true, greeting_name: nil)
    assert_equal user.full_name, user.reload.greeting_name
  end

  test 'auto_fill_greeting_name sets name from username when use_username_for_greeting' do
    user = users(:one)
    user.update!(use_full_name_for_greeting: false, use_username_for_greeting: true)
    assert_equal user.username, user.reload.greeting_name
  end

  test 'clear_greeting_name_if_do_not_greet clears the greeting name' do
    user = users(:one)
    user.update!(greeting_name: 'Sparky', use_full_name_for_greeting: false,
                 use_username_for_greeting: false, do_not_greet: true)
    assert_nil user.reload.greeting_name
  end

  test 'custom greeting name is preserved when no boolean is set' do
    user = users(:one)
    user.update!(
      use_full_name_for_greeting: false,
      use_username_for_greeting: false,
      do_not_greet: false,
      greeting_name: 'Sparky'
    )
    assert_equal 'Sparky', user.reload.greeting_name
    assert_equal 'custom', user.greeting_option
  end
end
