require 'test_helper'

class DefaultSettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'should get show' do
    get default_settings_url
    assert_response :success
  end

  test 'should get edit' do
    get edit_default_settings_url
    assert_response :success
  end

  test 'should update default settings' do
    patch default_settings_url, params: {
      default_setting: { site_prefix: 'test-prefix' }
    }
    assert_redirected_to default_settings_url
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
