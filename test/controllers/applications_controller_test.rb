require 'test_helper'

class ApplicationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @application = applications(:sample_app)
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'should get index' do
    get applications_url
    assert_response :success
  end

  test 'should get show' do
    get application_url(@application)
    assert_response :success
  end

  test 'should get new' do
    get new_application_url
    assert_response :success
  end

  test 'should create application' do
    assert_difference('Application.count') do
      post applications_url, params: {
        application: { name: 'New App', internal_url: 'http://new.local', external_url: 'https://new.example.com' }
      }
    end
    assert_redirected_to application_url(Application.last)
  end

  test 'should get edit' do
    get edit_application_url(@application)
    assert_response :success
  end

  test 'should update application' do
    patch application_url(@application), params: {
      application: { name: 'Updated App' }
    }
    assert_redirected_to application_url(@application)
  end

  test 'should destroy application' do
    assert_difference('Application.count', -1) do
      delete application_url(@application)
    end
    assert_redirected_to applications_url
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
