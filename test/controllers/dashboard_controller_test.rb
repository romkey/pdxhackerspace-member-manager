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

    assert_match(/Needs Attention/i, response.body)
    assert_match(/No Action Required/i, response.body)
    assert_match(/Open training requests/i, response.body)
  end

  test 'admin home includes normal user tabs' do
    get root_path(tab: :payments)
    assert_response :success
    assert_match(/Payment Events/i, response.body)

    get root_path(tab: :profile)
    assert_response :success

    get root_path(tab: :member_dashboard)
    assert_response :success
    assert_match(/Request Training/i, response.body)
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
