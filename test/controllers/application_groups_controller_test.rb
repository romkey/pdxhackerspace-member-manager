require 'test_helper'

class ApplicationGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @application = applications(:sample_app)
    @application_group = application_groups(:sample_group)
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'should get show' do
    get application_application_group_url(@application, @application_group)
    assert_response :success
  end

  test 'should get edit' do
    get edit_application_application_group_url(@application, @application_group)
    assert_response :success
  end

  test 'should update application group' do
    patch application_application_group_url(@application, @application_group), params: {
      application_group: { name: 'Updated Group' }
    }
    assert_response :redirect
  end

  test 'should add user' do
    user = users(:one)
    post add_user_application_application_group_url(@application, @application_group), params: {
      user_id: user.id
    }
    assert_response :redirect
  end

  test 'should remove user' do
    user = users(:one)
    @application_group.users << user unless @application_group.users.include?(user)
    delete remove_user_application_application_group_url(@application, @application_group), params: {
      user_id: user.id
    }
    assert_response :redirect
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
