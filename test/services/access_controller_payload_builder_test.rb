require 'test_helper'

class AccessControllerPayloadBuilderTest < ActiveSupport::TestCase
  setup do
    @user_one = users(:one)
    @user_two = users(:two)
    @laser_controller = access_controller_types(:laser_controller)
    @door_lock = access_controller_types(:door_lock)
    @laser_topic = training_topics(:laser_cutting)
    @woodworking_topic = training_topics(:woodworking)
  end

  # --- Global active/inactive filtering ---

  test 'only includes active users by default' do
    payload = parse_payload
    uids = payload.map { |u| u['uid'] }

    active_with_rfids = User.active.joins(:rfids).distinct
    active_with_rfids.each do |user|
      assert_includes uids, (user.authentik_id.presence || user.id),
                      "Expected active user #{user.display_name} in payload"
    end
  end

  test 'excludes inactive users by default' do
    @user_one.update!(active: false)

    payload = parse_payload
    uids = payload.map { |u| u['uid'] }
    refute_includes uids, @user_one.authentik_id
  end

  test 'includes inactive users when sync_inactive_members is enabled' do
    @user_one.update!(active: false)
    DefaultSetting.instance.update!(sync_inactive_members: true)

    payload = parse_payload
    uids = payload.map { |u| u['uid'] }
    assert_includes uids, @user_one.authentik_id
  end

  test 'excludes users without RFID cards regardless of active status' do
    @user_one.rfids.destroy_all

    payload = parse_payload
    uids = payload.map { |u| u['uid'] }
    refute_includes uids, @user_one.authentik_id
  end

  # --- Per-type training topic filtering ---

  test 'includes all users when no training topics required' do
    # door_lock has no required topics
    payload = parse_payload(access_controller_type: @door_lock)
    uids = payload.map { |u| u['uid'] }

    assert_includes uids, @user_one.authentik_id
    assert_includes uids, @user_two.authentik_id
  end

  test 'only includes users trained in required topics' do
    # laser_controller requires laser_cutting (via fixture)
    # Train user_one in laser cutting
    Training.create!(trainee: @user_one, training_topic: @laser_topic, trained_at: 1.day.ago)

    payload = parse_payload(access_controller_type: @laser_controller)
    uids = payload.map { |u| u['uid'] }

    assert_includes uids, @user_one.authentik_id
    refute_includes uids, @user_two.authentik_id
  end

  test 'requires ALL topics when multiple are set' do
    # Add woodworking as a second requirement for laser_controller
    @laser_controller.required_training_topics << @woodworking_topic

    # Train user_one in laser cutting only (not woodworking)
    Training.create!(trainee: @user_one, training_topic: @laser_topic, trained_at: 1.day.ago)

    payload = parse_payload(access_controller_type: @laser_controller)
    uids = payload.map { |u| u['uid'] }
    refute_includes uids, @user_one.authentik_id, 'User trained in only one of two required topics should be excluded'

    # Now train user_one in woodworking too
    Training.create!(trainee: @user_one, training_topic: @woodworking_topic, trained_at: 1.day.ago)

    payload = parse_payload(access_controller_type: @laser_controller)
    uids = payload.map { |u| u['uid'] }
    assert_includes uids, @user_one.authentik_id, 'User trained in both required topics should be included'
  end

  test 'no type passed includes all active users with RFIDs' do
    # When called without an access_controller_type, no training filter is applied
    payload = parse_payload(access_controller_type: nil)
    uids = payload.map { |u| u['uid'] }

    assert_includes uids, @user_one.authentik_id
    assert_includes uids, @user_two.authentik_id
  end

  test 'payload includes permissions for each user' do
    Training.create!(trainee: @user_one, training_topic: @laser_topic, trained_at: 1.day.ago)
    Training.create!(trainee: @user_one, training_topic: @woodworking_topic, trained_at: 1.day.ago)

    payload = parse_payload
    user_entry = payload.find { |u| u['uid'] == @user_one.authentik_id }

    assert_includes user_entry['permissions'], 'Laser Cutting'
    assert_includes user_entry['permissions'], 'Woodworking'
  end

  # --- Model method tests ---

  test 'user_meets_training_requirements? returns true when no topics required' do
    assert @door_lock.user_meets_training_requirements?(@user_one)
  end

  test 'user_meets_training_requirements? returns false when user lacks training' do
    refute @laser_controller.user_meets_training_requirements?(@user_one)
  end

  test 'user_meets_training_requirements? returns true when user has required training' do
    Training.create!(trainee: @user_one, training_topic: @laser_topic, trained_at: 1.day.ago)
    assert @laser_controller.user_meets_training_requirements?(@user_one)
  end

  private

  def parse_payload(access_controller_type: nil)
    json = AccessControllerPayloadBuilder.call(access_controller_type: access_controller_type)
    JSON.parse(json)
  end
end
