require "test_helper"
require "active_job/test_helper"

class RechargePaymentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as_local_admin
    @payment = recharge_payments(:recharge_payment)
  end

  test "shows index" do
    get recharge_payments_path
    assert_response :success
    assert_select "h1", /Recharge Payments/
    assert_match @payment.recharge_id, response.body
  end

  test "shows payment" do
    get recharge_payment_path(@payment)
    assert_response :success
    assert_match @payment.recharge_id, response.body
  end

  test "enqueues sync job" do
    assert_enqueued_with(job: Recharge::PaymentSyncJob) do
      post sync_recharge_payments_path
    end
    assert_redirected_to recharge_payments_path
  end

  private

  def sign_in_as_local_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: {
        email: account.email,
        password: "localpassword123"
      }
    }
  end
end

