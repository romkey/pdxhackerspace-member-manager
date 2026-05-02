require 'test_helper'

class DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'admin home defaults to admin dashboard tab' do
    get root_path
    assert_response :success

    assert_match(/Admin Dashboard/i, response.body)
    assert_match(/Member Dashboard/i, response.body)
    assert_match(/Find a member by name, email or username/i, response.body)
    assert_match(/Recent Highlights/i, response.body)
  end

  test 'admin home member dashboard tab renders member dashboard content' do
    get root_path(tab: :member_dashboard)
    assert_response :success

    assert_match(/Quick actions/i, response.body)
    assert_match(/Membership/i, response.body)
    assert_match(/Request training/i, response.body)
  end

  test 'admin home includes normal user tabs' do
    get root_path(tab: :payments)
    assert_response :success
    assert_match(/Payment Events/i, response.body)

    get root_path(tab: :profile)
    assert_response :success

    get root_path(tab: :member_dashboard)
    assert_response :success
    assert_match(/Request training/i, response.body)
  end

  test 'home messages nav badge only shows unread count' do
    admin_user = User.find_by!(email: local_accounts(:active_admin).email)
    Message.where(recipient: admin_user).destroy_all
    Message.create!(
      sender: users(:one),
      recipient: admin_user,
      subject: 'Read home message',
      body: 'Already read',
      read_at: Time.current
    )

    get root_path

    assert_response :success
    assert_select 'a.nav-link[href=?]', messages_path(folder: :unread) do
      assert_select '.badge', count: 0
    end
  end

  test 'admin dashboard urgent items come from shared urgent snapshot' do
    snapshot = AdminDashboard::UrgentItems::Snapshot.new(
      [],
      0,
      2,
      3,
      4,
      9,
      [],
      nil,
      false,
      nil,
      [],
      false,
      [],
      []
    )

    original_snapshot = AdminDashboard::UrgentItems.method(:snapshot)
    AdminDashboard::UrgentItems.define_singleton_method(:snapshot) { |**_kwargs| snapshot }
    begin
      get root_path
    ensure
      AdminDashboard::UrgentItems.define_singleton_method(:snapshot, original_snapshot)
    end

    assert_response :success
    assert_match(%r{9</strong> access controller issues}, response.body)
    assert_match(/2 offline, 3 sync failed, 4 backup failed/, response.body)
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: 'localpassword123'
      }
    }
  end
end
