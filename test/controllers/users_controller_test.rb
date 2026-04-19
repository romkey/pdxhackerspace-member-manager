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

  test 'admin profile tab links to linked membership applications' do
    app = MembershipApplication.create!(
      email: 'profile-link-test@example.com',
      user: @user,
      status: 'approved',
      submitted_at: 1.day.ago,
      reviewed_at: Time.current
    )

    get user_path(@user, tab: :profile)

    assert_response :success
    assert_select 'a[href=?]', membership_application_path(app), text: /Application ##{app.id}/
  end

  test 'member profile does not show membership application links' do
    member = users(:member_with_local_account)
    app = MembershipApplication.create!(
      email: 'member-hidden-app@example.com',
      user: member,
      status: 'approved',
      submitted_at: 1.day.ago,
      reviewed_at: Time.current
    )

    delete logout_path
    sign_in_as_regular_member

    get user_path(member, tab: :profile)

    assert_response :success
    assert_select 'a[href=?]', membership_application_path(app), count: 0
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
