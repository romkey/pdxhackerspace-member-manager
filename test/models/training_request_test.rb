require 'test_helper'

class TrainingRequestTest < ActiveSupport::TestCase
  test 'cannot create duplicate pending request for same user and topic' do
    existing = training_requests(:pending_laser_request)

    duplicate = TrainingRequest.new(
      user: existing.user,
      training_topic: existing.training_topic,
      share_contact_info: true,
      status: 'pending'
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:training_topic_id], 'already has an active request for this member'
  end

  test 'allows new request for same user and topic when previous request was responded' do
    responded = training_requests(:responded_woodworking_request)
    request = TrainingRequest.new(
      user: responded.user,
      training_topic: responded.training_topic,
      share_contact_info: true,
      status: 'pending'
    )

    assert request.valid?
  end
end
