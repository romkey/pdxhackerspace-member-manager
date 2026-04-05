# frozen_string_literal: true

require 'test_helper'

class MembershipApplicationAcceptanceVoteTest < ActiveSupport::TestCase
  setup do
    @app = MembershipApplication.create!(
      email: 'accept-vote-test@example.com',
      status: 'submitted',
      submitted_at: Time.current
    )
    @user = users(:one)
  end

  test 'valid accept vote' do
    v = MembershipApplicationAcceptanceVote.new(
      membership_application: @app,
      user: @user,
      decision: 'accept'
    )
    assert v.valid?
    assert v.save
  end

  test 'one vote per user per application' do
    MembershipApplicationAcceptanceVote.create!(
      membership_application: @app,
      user: @user,
      decision: 'accept'
    )
    dup = MembershipApplicationAcceptanceVote.new(
      membership_application: @app,
      user: @user,
      decision: 'reject'
    )
    assert_not dup.valid?
  end
end
