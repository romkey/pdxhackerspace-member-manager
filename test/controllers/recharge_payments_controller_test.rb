require 'test_helper'
require 'active_job/test_helper'

class RechargePaymentsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_local_admin
    @payment = recharge_payments(:recharge_payment)
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'shows index' do
    get recharge_payments_path
    assert_response :success
    assert_select 'h1', /Recharge payments/i
    assert_match @payment.recharge_id, response.body
  end

  test 'shows payment' do
    get recharge_payment_path(@payment)
    assert_response :success
    assert_match @payment.recharge_id, response.body
  end

  test 'enqueues sync job' do
    assert_enqueued_with(job: Recharge::PaymentSyncJob) do
      post sync_recharge_payments_path
    end
    assert_redirected_to recharge_payments_path
  end

  test 'live search is rendered as server search without retaining pagination' do
    get recharge_payments_path(page: 2, q: 'pagination target')

    assert_response :success
    assert_select 'form[action=?][method=get]', recharge_payments_path do
      assert_select 'input[name=q][value=?]', 'pagination target'
      assert_select 'input[name=page]', count: 0
    end
  end

  test 'payment search paginates the filtered result set' do
    105.times do |index|
      RechargePayment.create!(
        recharge_id: "RC-PAGE-FILLER-#{index}",
        status: 'success',
        amount: 30.00,
        currency: 'USD',
        processed_at: Time.current - index.minutes,
        customer_email: "recharge-filler-#{index}@example.com",
        customer_name: "Recharge Filler #{index}"
      )
    end
    target = RechargePayment.create!(
      recharge_id: 'RC-LIVE-SEARCH-TARGET',
      status: 'success',
      amount: 30.00,
      currency: 'USD',
      processed_at: 1.year.ago,
      customer_email: 'recharge-live-search-target@example.com',
      customer_name: 'Recharge Live Search Pagination Target'
    )

    get recharge_payments_path
    assert_response :success
    assert_no_match target.recharge_id, response.body

    get recharge_payments_path(q: 'Live Search Pagination Target')
    assert_response :success
    assert_match target.recharge_id, response.body
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
