require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_local_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'shows user profile' do
    get user_path(@user)
    assert_response :success
    assert_match @user.display_name, response.body
  end

  test 'shows user with payment history on payments tab' do
    get user_path(@user, tab: :payments)
    assert_response :success
    assert_match @user.display_name, response.body
    assert_match(/Payment Events/i, response.body)
  end

  # ─── Disabled Source Guards ──────────────────────────────────────

  test 'sync from authentik redirects with alert when authentik source is disabled' do
    member_sources(:authentik).update!(enabled: false)

    post sync_users_path
    assert_redirected_to users_path
    assert_equal 'Authentik source is disabled.', flash[:alert]
  end

  test 'sync to authentik redirects with alert when member manager source is disabled' do
    member_sources(:member_manager).update!(enabled: false)

    post sync_all_to_authentik_users_path
    assert_redirected_to users_path
    assert_equal 'Member Manager source is disabled.', flash[:alert]
  end

  test 'per-user sync_to_authentik redirects with alert when member manager source is disabled' do
    member_sources(:member_manager).update!(enabled: false)

    post sync_to_authentik_user_path(@user)
    assert_redirected_to user_path(@user)
    assert_equal 'Member Manager source is disabled.', flash[:alert]
  end

  test 'per-user sync_from_authentik redirects with alert when authentik source is disabled' do
    member_sources(:authentik).update!(enabled: false)

    post sync_from_authentik_user_path(@user)
    assert_redirected_to user_path(@user)
    assert_equal 'Authentik source is disabled.', flash[:alert]
  end

  test 'create with duplicate email shows link to existing member profile' do
    post users_path, params: {
      user: {
        full_name: 'Duplicate Email Test',
        email: @user.email
      }
    }

    assert_response :unprocessable_content
    assert_select '.alert', text: /Unable to create member: email is already in use by/
    assert_select ".alert a[href='#{user_path(@user)}']", text: @user.display_name
  end

  private

  def sign_in_as_local_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: 'localpassword123'
      }
    }
  end
end
