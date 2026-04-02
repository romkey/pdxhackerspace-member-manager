require 'test_helper'

class MembershipPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_local_admin
    @user = users(:cash_payer)
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'mark_dues_received sets dues_due_at from plan billing cycle' do
    @user.update_columns(dues_due_at: nil, dues_status: 'lapsed', last_payment_date: 2.months.ago.to_date)
    post mark_dues_received_membership_plans_path, params: { user_id: @user.id }
    assert_redirected_to manual_payments_membership_plans_path
    @user.reload
    assert_equal 'current', @user.dues_status
    assert_equal Date.current + 1.month, @user.dues_due_at.to_date
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
