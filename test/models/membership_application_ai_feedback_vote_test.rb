# frozen_string_literal: true

require 'test_helper'

class MembershipApplicationAiFeedbackVoteTest < ActiveSupport::TestCase
  setup do
    @app = MembershipApplication.create!(email: 'vote-model@example.com', status: 'submitted')
    @user = users(:one)
  end

  test 'requires valid stance' do
    vote = MembershipApplicationAiFeedbackVote.new(
      membership_application: @app,
      user: @user,
      stance: 'maybe'
    )
    assert_not vote.valid?
    assert vote.errors.of_kind?(:stance, :inclusion)
  end

  test 'one vote per user per application' do
    MembershipApplicationAiFeedbackVote.create!(
      membership_application: @app,
      user: @user,
      stance: 'agree'
    )
    dup = MembershipApplicationAiFeedbackVote.new(
      membership_application: @app,
      user: @user,
      stance: 'disagree'
    )
    assert_not dup.valid?
  end
end
