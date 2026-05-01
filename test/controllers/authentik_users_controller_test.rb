require 'test_helper'
require 'active_job/test_helper'

class AuthentikUsersControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'sync enqueues job when authentik source is enabled' do
    assert_enqueued_with(job: Authentik::GroupSyncJob) do
      post sync_authentik_users_path
    end
    assert_redirected_to authentik_users_path
  end

  test 'sync redirects with alert when authentik source is disabled' do
    member_sources(:authentik).update!(enabled: false)

    assert_no_enqueued_jobs(only: Authentik::GroupSyncJob) do
      post sync_authentik_users_path
    end
    assert_redirected_to authentik_users_path
    assert_equal 'Authentik source is disabled.', flash[:alert]
  end

  test 'unlink_user disassociates authentik user and clears matching member authentik id' do
    user = users(:two)
    authentik_user = AuthentikUser.create!(
      authentik_id: user.authentik_id,
      username: 'auth-user',
      email: 'auth@example.com',
      full_name: 'Auth User',
      user: user
    )

    post unlink_user_authentik_user_path(authentik_user)

    assert_redirected_to authentik_user_path(authentik_user)
    assert_nil authentik_user.reload.user_id
    assert_nil user.reload.authentik_id
    assert_not user.authentik_dirty?
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
