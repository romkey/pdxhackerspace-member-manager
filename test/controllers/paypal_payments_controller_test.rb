require 'test_helper'
require 'active_job/test_helper'

class PaypalPaymentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as_local_admin
    @payment = paypal_payments(:sample_payment)
  end

  test 'shows index' do
    get paypal_payments_path
    assert_response :success
    assert_select 'h1', /PayPal Payments/
    assert_match @payment.paypal_id, response.body
  end

  test 'shows payment' do
    get paypal_payment_path(@payment)
    assert_response :success
    assert_match @payment.paypal_id, response.body
  end

  test 'enqueues sync job' do
    assert_enqueued_with(job: Paypal::PaymentSyncJob) do
      post sync_paypal_payments_path
    end
    assert_redirected_to paypal_payments_path
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
