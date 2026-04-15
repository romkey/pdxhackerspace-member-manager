require 'test_helper'

class TrainingRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @topic = training_topics(:woodworking)
    TrainerCapability.find_or_create_by!(user: users(:one), training_topic: @topic)
    TrainerCapability.find_or_create_by!(user: users(:two), training_topic: @topic)
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'member can request training for offered topic' do
    sign_in_as_member
    member = User.find_by(authentik_id: "local:#{local_accounts(:regular_member).id}")

    assert_difference 'TrainingRequest.count', 1 do
      assert_difference 'QueuedMail.count', 3 do
        post training_requests_path, params: {
          training_request: {
            training_topic_id: @topic.id,
            share_contact_info: '1'
          }
        }
      end
    end

    request = TrainingRequest.order(:created_at).last
    assert_equal 'pending', request.status
    assert_redirected_to user_path(member, tab: :profile)
  end

  test 'member must consent to sharing contact info' do
    sign_in_as_member

    assert_no_difference 'TrainingRequest.count' do
      post training_requests_path, params: {
        training_request: {
          training_topic_id: @topic.id,
          share_contact_info: '0'
        }
      }
    end

    assert_redirected_to new_training_request_path
    assert_equal 'Please confirm contact sharing to submit your request.', flash[:alert]
  end

  test 'member can open new training request page' do
    sign_in_as_member

    get new_training_request_path
    assert_response :success
    assert_match(/Request Training/i, response.body)
    assert_match 'name="training_request[training_topic_id]"', response.body
    assert_match 'name="training_request[share_contact_info]"', response.body
  end

  test 'trainer can open response form for request in their topic' do
    trainer = sign_in_as_trainer
    TrainerCapability.find_or_create_by!(user: trainer, training_topic: training_topics(:laser_cutting))

    get edit_training_request_path(training_requests(:pending_laser_request))
    assert_response :success
  end

  test 'member cannot open response form for request' do
    sign_in_as_member

    get edit_training_request_path(training_requests(:pending_laser_request))
    assert_redirected_to user_path(User.find_by(authentik_id: "local:#{local_accounts(:regular_member).id}"))
  end

  test 'trainer can respond to request in member manager' do
    trainer = sign_in_as_trainer
    TrainerCapability.find_or_create_by!(user: trainer, training_topic: training_topics(:laser_cutting))
    request = training_requests(:pending_laser_request)

    assert_difference 'Message.count', 1 do
      patch training_request_path(request), params: {
        training_request: {
          response_body: 'Happy to help. Please message me in #help to schedule.'
        }
      }
    end

    request.reload
    assert_equal 'responded', request.status
    assert_equal trainer, request.responded_by
    assert_not_nil request.responded_at
  end

  test 'member dashboard links to training request page' do
    sign_in_as_member
    member = User.find_by(authentik_id: "local:#{local_accounts(:regular_member).id}")

    get user_path(member)
    assert_response :success
    assert_match(/Request Training/i, response.body)
    assert_match(new_training_request_path, response.body)
  end

  private

  def sign_in_as_member
    post local_login_path, params: {
      session: { email: local_accounts(:regular_member).email, password: 'memberpassword123' }
    }
  end

  def sign_in_as_trainer
    post local_login_path, params: {
      session: { email: local_accounts(:trainer_account).email, password: 'trainerpassword123' }
    }
    User.find_by(authentik_id: "local:#{local_accounts(:trainer_account).id}")
  end
end
