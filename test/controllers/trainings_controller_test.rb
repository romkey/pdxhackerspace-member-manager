require 'test_helper'

class TrainingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    @laser_topic = training_topics(:laser_cutting)
    @woodworking_topic = training_topics(:woodworking)
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'trainer sees only topics they can train and no topic edit links' do
    trainer = sign_in_as_trainer
    TrainerCapability.create!(user: trainer, training_topic: @laser_topic)

    get train_member_path

    assert_response :success
    assert_match 'Laser Cutting', response.body
    assert_no_match 'Woodworking', response.body
    assert_select 'a[href=?]', edit_training_topic_path(@laser_topic), count: 0
    assert_no_match 'Manage Training Topics', response.body
  end

  test 'trainer can add training for a topic they can train' do
    trainer = sign_in_as_trainer
    trainee = users(:no_email)
    TrainerCapability.create!(user: trainer, training_topic: @laser_topic)

    assert_difference 'Training.count', 1 do
      post add_training_path(user_id: trainee.id, topic_id: @laser_topic.id)
    end

    assert_redirected_to train_member_path(user_id: trainee.id)
    assert Training.exists?(trainee: trainee, trainer: trainer, training_topic: @laser_topic)
  end

  test 'trainer cannot add training for a topic they cannot train' do
    trainer = sign_in_as_trainer
    trainee = users(:no_email)
    TrainerCapability.create!(user: trainer, training_topic: @laser_topic)

    assert_no_difference 'Training.count' do
      post add_training_path(user_id: trainee.id, topic_id: @woodworking_topic.id)
    end

    assert_redirected_to train_member_path
  end

  test 'regular member cannot access train a member' do
    sign_in_as_regular_member

    get train_member_path

    assert_redirected_to root_path
  end

  private

  def sign_in_as_trainer
    account = local_accounts(:trainer_account)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: 'trainerpassword123'
      }
    }
    User.find_by!(authentik_id: "local:#{account.id}")
  end

  def sign_in_as_regular_member
    account = local_accounts(:regular_member)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: 'memberpassword123'
      }
    }
  end
end
