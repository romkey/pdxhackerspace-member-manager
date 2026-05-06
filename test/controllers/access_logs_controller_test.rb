require 'test_helper'

class AccessLogsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_local_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  # ─── Index ─────────────────────────────────────────────────────────

  test 'index loads successfully' do
    get access_logs_path
    assert_response :success
  end

  test 'index shows linked and unlinked counts' do
    get access_logs_path
    assert_response :success
    # Should display badge counts
    assert_match 'Linked', response.body
    assert_match 'Unlinked', response.body
  end

  test 'index filters by linked=yes' do
    get access_logs_path(linked: 'yes')
    assert_response :success
  end

  test 'index filters by linked=no' do
    get access_logs_path(linked: 'no')
    assert_response :success
  end

  test 'link modal can search members by email and username' do
    user = users(:one)

    get access_logs_path
    assert_response :success

    assert_select '.link-user-item[data-user-email=?][data-username=?]', user.email, user.username
  end

  # ─── Link User ─────────────────────────────────────────────────────

  test 'link_user links access log to a member' do
    log = access_logs(:unlinked_entry)
    user = users(:two)

    post link_user_access_log_path(log), params: { user_id: user.id }
    assert_redirected_to access_logs_path

    log.reload
    assert_equal user.id, log.user_id
  end

  test 'link_user adds name as alias if different from full_name' do
    log = access_logs(:unlinked_entry)
    user = users(:two)
    user.update_columns(aliases: [])

    post link_user_access_log_path(log), params: { user_id: user.id }

    user.reload
    assert_includes user.aliases, 'Unknown Person'
  end

  test 'link_user also links other entries with the same name' do
    log = access_logs(:unlinked_entry)
    other_log = access_logs(:another_unlinked)
    user = users(:two)

    post link_user_access_log_path(log), params: { user_id: user.id }

    other_log.reload
    assert_equal user.id, other_log.user_id, 'other unlinked entries with same name should be linked too'
  end

  # ─── Create Member ─────────────────────────────────────────────────

  test 'create_member creates a new member from access log' do
    log = access_logs(:unlinked_entry)

    assert_difference 'User.count', 1 do
      post create_member_access_log_path(log)
    end

    log.reload
    assert_not_nil log.user_id

    new_user = User.find(log.user_id)
    assert_equal 'Unknown Person', new_user.full_name
  end

  test 'create_member links other entries with same name' do
    log = access_logs(:unlinked_entry)
    other_log = access_logs(:another_unlinked)

    post create_member_access_log_path(log)

    log.reload
    other_log.reload
    assert_equal log.user_id, other_log.user_id, 'other entries with same name should be linked to new member'
  end

  test 'create_member rejects already-linked log' do
    log = access_logs(:linked_entry)

    assert_no_difference 'User.count' do
      post create_member_access_log_path(log)
    end

    assert_redirected_to access_logs_path
    follow_redirect!
    assert_match(/already linked/, response.body)
  end

  private

  def sign_in_as_local_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
