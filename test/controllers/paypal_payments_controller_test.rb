require 'test_helper'
require 'active_job/test_helper'

class PaypalPaymentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_local_admin
    @payment = paypal_payments(:sample_payment)
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
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

  test 'live search is rendered as server search without retaining pagination' do
    get paypal_payments_path(page: 2, q: 'pagination target')

    assert_response :success
    assert_select 'form[action=?][method=get][data-turbo-frame=?]', paypal_payments_path, 'paypal_payments_results' do
      assert_select 'input[name=q][value=?]', 'pagination target'
      assert_select 'input[name=page]', count: 0
    end
    assert_select 'turbo-frame[id=?]', 'paypal_payments_results'
  end

  test 'payment search paginates the filtered result set' do
    105.times do |index|
      PaypalPayment.create!(
        paypal_id: "PAY-PAGE-FILLER-#{index}",
        status: 'COMPLETED',
        amount: 42.50,
        currency: 'USD',
        transaction_time: Time.current - index.minutes,
        transaction_type: 'T0001',
        payer_email: "paypal-filler-#{index}@example.com",
        payer_name: "PayPal Filler #{index}",
        payer_id: "PAYER-FILLER-#{index}",
        matches_plan: true
      )
    end
    target = PaypalPayment.create!(
      paypal_id: 'PAY-LIVE-SEARCH-TARGET',
      status: 'COMPLETED',
      amount: 42.50,
      currency: 'USD',
      transaction_time: 1.year.ago,
      transaction_type: 'T0001',
      payer_email: 'paypal-live-search-target@example.com',
      payer_name: 'PayPal Live Search Pagination Target',
      payer_id: 'PAYER-LIVE-SEARCH-TARGET',
      matches_plan: true
    )

    get paypal_payments_path
    assert_response :success
    assert_no_match target.paypal_id, response.body

    get paypal_payments_path(q: 'Live Search Pagination Target')
    assert_response :success
    assert_match target.paypal_id, response.body
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
