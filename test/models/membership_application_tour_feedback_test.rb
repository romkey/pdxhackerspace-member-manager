# frozen_string_literal: true

require 'test_helper'

class MembershipApplicationTourFeedbackTest < ActiveSupport::TestCase
  setup do
    @app = MembershipApplication.create!(
      email: 'tour-fb-test@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    @user = users(:one)
  end

  test 'requires at least one text field' do
    fb = MembershipApplicationTourFeedback.new(membership_application: @app, user: @user)
    assert_not fb.valid?
    fb.attitude = 'Friendly'
    assert fb.valid?
  end

  test 'one feedback per user per application' do
    MembershipApplicationTourFeedback.create!(
      membership_application: @app,
      user: @user,
      attitude: 'Great'
    )
    dup = MembershipApplicationTourFeedback.new(
      membership_application: @app,
      user: @user,
      impressions: 'Second try'
    )
    assert_not dup.valid?
    assert dup.errors.of_kind?(:user_id, :taken)
  end
end
