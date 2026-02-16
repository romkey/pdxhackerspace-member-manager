require 'test_helper'

class UsersLegacyFilterTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_local_admin

    @legacy_user = User.create!(
      authentik_id: "legacy-filter-#{SecureRandom.hex(4)}",
      full_name: 'Legacy Filter Member',
      payment_type: 'unknown',
      legacy: true
    )
    @regular_user = users(:one)
    @regular_user.update_columns(legacy: false)
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'index excludes legacy members by default' do
    get users_path
    assert_response :success
    assert_no_match(/Legacy Filter Member/, response.body)
    assert_match @regular_user.display_name, response.body
  end

  test 'include_legacy checkbox includes legacy members in list' do
    get users_path(include_legacy: '1')
    assert_response :success
    assert_match 'Legacy Filter Member', response.body
    assert_match @regular_user.display_name, response.body
  end

  test 'include legacy checkbox is shown in account type section' do
    get users_path
    assert_response :success
    assert_match 'Include legacy', response.body
  end

  test 'include_legacy checkbox is checked when param is present' do
    get users_path(include_legacy: '1')
    assert_response :success
    assert_match 'checked', response.body
  end

  test 'legacy user shows legacy badge in table row when include_legacy is checked' do
    get users_path(include_legacy: '1')
    assert_response :success
    assert_match 'bi-archive', response.body
  end

  test 'admin can mark a member as legacy via edit' do
    patch user_path(@regular_user), params: { user: { legacy: '1' } }
    @regular_user.reload
    assert @regular_user.legacy?, 'Member should be marked as legacy'
  end

  test 'admin can un-mark a legacy member via edit' do
    patch user_path(@legacy_user), params: { user: { legacy: '0' } }
    @legacy_user.reload
    assert_not @legacy_user.legacy?, 'Member should be un-marked as legacy'
  end

  private

  def sign_in_as_local_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
