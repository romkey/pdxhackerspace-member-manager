require 'test_helper'

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @local_account = local_accounts(:active_admin)
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'local login signs in the user' do
    post local_login_path, params: {
      session: {
        email: @local_account.email,
        password: 'localpassword123'
      }
    }

    assert_redirected_to root_path
    follow_redirect!
    assert_response :success
    assert_match 'Signed in locally', response.body
  end

  test 'local login fails with bad credentials' do
    post local_login_path, params: {
      session: {
        email: @local_account.email,
        password: 'wrongpassword'
      }
    }

    assert_response :unprocessable_entity
    assert_select '.alert', /Invalid email or password/
  end

  test 'rfid login redirects to wait page' do
    post rfid_login_path
    assert_redirected_to rfid_wait_path
  end

  test 'rfid wait without session redirects to login' do
    get rfid_wait_path
    assert_redirected_to login_path
  end

  test 'rfid login stores session timestamp' do
    post rfid_login_path
    assert_redirected_to rfid_wait_path
    follow_redirect!
    assert_response :success
  end
end
