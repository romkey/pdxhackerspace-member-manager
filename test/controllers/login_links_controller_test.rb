require 'test_helper'

class LoginLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    ENV['LOCAL_AUTH_ENABLED'] = 'true'
  end

  teardown do
    ENV.delete('LOCAL_AUTH_ENABLED')
  end

  # --- Show (requires auth) ---

  test 'show redirects to login when not authenticated' do
    get login_link_url
    assert_redirected_to login_path
  end

  test 'show renders when authenticated' do
    sign_in_as_member
    get login_link_url
    assert_response :success
  end

  test 'show displays active login link' do
    sign_in_as_member
    user = current_logged_in_user
    user.generate_login_token!

    get login_link_url
    assert_response :success
    assert_match user.login_token, response.body
  end

  # --- Regenerate ---

  test 'regenerate creates a login token' do
    sign_in_as_member
    user = current_logged_in_user
    assert_nil user.login_token

    post login_link_regenerate_url
    assert_redirected_to login_link_path

    user.reload
    assert_not_nil user.login_token
    assert_equal 64, user.login_token.length
    assert_not_nil user.login_token_expires_at
  end

  test 'regenerate replaces existing token' do
    sign_in_as_member
    user = current_logged_in_user
    user.generate_login_token!
    old_token = user.login_token

    post login_link_regenerate_url
    user.reload
    assert_not_equal old_token, user.login_token
  end

  # --- Authenticate (token login) ---

  test 'authenticate signs in with valid token' do
    user = users(:one)
    user.generate_login_token!

    get login_link_authenticate_url(token: user.login_token)
    assert_redirected_to root_path
    assert_equal user.id, session[:user_id]
  end

  test 'authenticate rejects invalid token' do
    get login_link_authenticate_url(token: 'nonexistent_token_abc123')
    assert_redirected_to login_path
    assert_nil session[:user_id]
  end

  test 'authenticate rejects expired token' do
    user = users(:one)
    user.update!(
      login_token: SecureRandom.alphanumeric(64),
      login_token_expires_at: 1.day.ago
    )

    get login_link_authenticate_url(token: user.login_token)
    assert_redirected_to login_path
    assert_nil session[:user_id]

    user.reload
    assert_nil user.login_token
  end

  test 'authenticate queues expiration email for expired token' do
    user = users(:one)
    user.update!(
      login_token: SecureRandom.alphanumeric(64),
      login_token_expires_at: 1.day.ago
    )

    assert_difference 'QueuedMail.count', 1 do
      get login_link_authenticate_url(token: user.login_token)
    end
  end

  private

  def sign_in_as_member
    account = local_accounts(:regular_member)
    Rails.application.config.x.local_auth.enabled = true
    post local_login_path, params: {
      session: { email: account.email, password: 'memberpassword123' }
    }
  end

  def current_logged_in_user
    User.find(session[:user_id])
  end
end
