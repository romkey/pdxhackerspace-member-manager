require 'test_helper'

class SlackUsersControllerTest < ActionDispatch::IntegrationTest
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
    get slack_users_path
    assert_response :success
  end

  test 'index shows linked and unlinked counts' do
    get slack_users_path
    assert_response :success
    assert_match 'Linked', response.body
    assert_match 'Unlinked', response.body
  end

  test 'index status filters split active inactive and deactivated accounts' do
    recent = SlackUser.create!(slack_id: 'URECENTFILTER', display_name: 'Recent Slack', last_active_at: 1.month.ago)
    inactive = SlackUser.create!(slack_id: 'UINACTIVEFILTER', display_name: 'Dormant Slack', last_active_at: nil)
    deactivated = SlackUser.create!(slack_id: 'UDEACTIVATEDFILTER', display_name: 'Disabled Slack', deleted: true,
                                    last_active_at: 1.month.ago)

    get slack_users_path(status: 'active')
    assert_response :success
    assert_match recent.display_name, response.body
    assert_no_match inactive.display_name, response.body
    assert_no_match deactivated.display_name, response.body

    get slack_users_path(status: 'inactive')
    assert_response :success
    assert_match inactive.display_name, response.body
    assert_no_match recent.display_name, response.body
    assert_no_match deactivated.display_name, response.body
  end

  test 'apply_status_filter returns the requested status scope' do
    recent = SlackUser.create!(slack_id: 'URECENTHELPER', last_active_at: 1.month.ago)
    inactive = SlackUser.create!(slack_id: 'UINACTIVEHELPER', last_active_at: nil)
    deactivated = SlackUser.create!(slack_id: 'UDEACTIVATEDHELPER', deleted: true, last_active_at: 1.month.ago)
    scope = SlackUser.where(id: [recent.id, inactive.id, deactivated.id])

    assert_equal [recent.id], status_filter_ids(scope, 'active')
    assert_equal [inactive.id], status_filter_ids(scope, 'inactive')
    assert_equal [deactivated.id], status_filter_ids(scope, 'deactivated')
    assert_equal [recent.id, inactive.id, deactivated.id].sort, status_filter_ids(scope, 'unknown').sort
  end

  # ─── Link User ─────────────────────────────────────────────────────

  test 'link_user links slack user to a member' do
    slack_user = slack_users(:with_dept)
    user = users(:two)

    post link_user_slack_user_path(slack_user), params: { user_id: user.id }

    slack_user.reload
    assert_equal user.id, slack_user.user_id
  end

  test 'link_user does not copy slack profile data to member' do
    slack_user = slack_users(:with_dept)
    user = users(:two)
    user.update_columns(aliases: [], slack_id: nil, slack_handle: nil, avatar: nil)

    post link_user_slack_user_path(slack_user), params: { user_id: user.id }

    user.reload
    assert_empty user.aliases
    assert_nil user.slack_id
    assert_nil user.slack_handle
    assert_nil user.avatar
  end

  test 'link_user from index redirects back to index' do
    slack_user = slack_users(:with_dept)
    user = users(:two)

    post link_user_slack_user_path(slack_user), params: { user_id: user.id, from_index: 'true' }
    assert_redirected_to slack_users_path
  end

  # ─── Toggle Don't Link ─────────────────────────────────────────────

  test 'toggle_dont_link sets dont_link flag' do
    slack_user = slack_users(:with_dept)
    slack_user.update_columns(dont_link: false)

    post toggle_dont_link_slack_user_path(slack_user)

    slack_user.reload
    assert slack_user.dont_link?, 'dont_link should be set to true'
  end

  test 'toggle_dont_link unsets dont_link flag' do
    slack_user = slack_users(:with_dept)
    slack_user.update_columns(dont_link: true)

    post toggle_dont_link_slack_user_path(slack_user)

    slack_user.reload
    assert_not slack_user.dont_link?, 'dont_link should be set to false'
  end

  # ─── Create Member ─────────────────────────────────────────────────

  test 'create_member creates a new member from slack user' do
    slack_user = slack_users(:with_other_dept)
    slack_user.update_columns(user_id: nil)

    assert_difference 'User.count', 1 do
      post create_member_slack_user_path(slack_user)
    end

    slack_user.reload
    assert_not_nil slack_user.user_id

    new_user = User.find(slack_user.user_id)
    assert_equal 'Mary Jane', new_user.full_name
    assert_equal slack_user.email, new_user.email
    assert_equal slack_user.slack_id, new_user.slack_id
  end

  test 'create_member redirects to new member profile' do
    slack_user = slack_users(:with_other_dept)
    slack_user.update_columns(user_id: nil)

    post create_member_slack_user_path(slack_user)

    slack_user.reload
    new_user = User.find(slack_user.user_id)
    assert_redirected_to user_path(new_user)
  end

  # ─── Disabled Source Guards ──────────────────────────────────────

  test 'sync redirects with alert when slack source is disabled' do
    member_sources(:slack).update!(enabled: false)

    post sync_slack_users_path
    assert_redirected_to slack_users_path
    assert_equal 'Slack source is disabled.', flash[:alert]
  end

  test 'sync_to_users redirects with alert when slack source is disabled' do
    member_sources(:slack).update!(enabled: false)

    post sync_to_users_slack_users_path
    assert_redirected_to slack_users_path
    assert_equal 'Slack source is disabled.', flash[:alert]
  end

  # ─── Create Member ─────────────────────────────────────────────

  test 'create_member rejects already-linked slack user' do
    slack_user = slack_users(:with_dept)
    slack_user.update_columns(user_id: users(:one).id)

    assert_no_difference 'User.count' do
      post create_member_slack_user_path(slack_user)
    end

    assert_redirected_to slack_users_path
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

  def status_filter_ids(scope, status)
    controller = SlackUsersController.new
    controller.params = ActionController::Parameters.new(status: status)
    controller.send(:apply_status_filter, scope).pluck(:id)
  end
end
