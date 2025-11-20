require 'test_helper'

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as_local_admin
  end

  test 'shows user with payment history' do
    get user_path(@user)
    assert_response :success
    assert_match @user.display_name, response.body
    assert_match paypal_payments(:sample_payment).paypal_id, response.body
    assert_match recharge_payments(:recharge_payment).recharge_id, response.body
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
