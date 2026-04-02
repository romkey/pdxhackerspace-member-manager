require 'test_helper'

class CashPaymentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_local_admin
    @payment = cash_payments(:sample_cash_payment)
    @user = users(:cash_payer)
    @plan = membership_plans(:personal_equipment_donation)
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'shows index' do
    get cash_payments_path
    assert_response :success
    assert_select 'h1', /Cash Payments/
  end

  test 'shows payment' do
    get cash_payment_path(@payment)
    assert_response :success
    assert_match @payment.identifier, response.body
  end

  test 'shows new form' do
    get new_cash_payment_path
    assert_response :success
    assert_select 'h1', /Record Cash Payment/
  end

  test 'shows new form with user_id prepopulated' do
    get new_cash_payment_path(user_id: @user.id)
    assert_response :success
  end

  test 'creates cash payment and updates user dues' do
    assert_difference('CashPayment.count', 1) do
      post cash_payments_path, params: {
        cash_payment: {
          user_id: @user.id,
          membership_plan_id: @plan.id,
          amount: 100.00,
          paid_on: Date.current,
          notes: 'Test payment'
        }
      }
    end
    assert_redirected_to cash_payment_path(CashPayment.last)

    @user.reload
    assert_equal 'current', @user.dues_status
    assert_equal 'cash', @user.payment_type
    assert @user.dues_due_at.present?
    assert_equal Date.current + 1.month, @user.dues_due_at.to_date
  end

  test 'create rejects invalid data' do
    assert_no_difference('CashPayment.count') do
      post cash_payments_path, params: {
        cash_payment: {
          user_id: @user.id,
          membership_plan_id: @plan.id,
          amount: 0,
          paid_on: Date.current
        }
      }
    end
    assert_response :unprocessable_content
  end

  test 'create rejects shared plan' do
    shared_plan = membership_plans(:monthly_standard)
    assert_no_difference('CashPayment.count') do
      post cash_payments_path, params: {
        cash_payment: {
          user_id: @user.id,
          membership_plan_id: shared_plan.id,
          amount: 50.00,
          paid_on: Date.current
        }
      }
    end
    assert_response :unprocessable_content
  end

  test 'shows edit form' do
    get edit_cash_payment_path(@payment)
    assert_response :success
    assert_select 'h1', /Edit Cash Payment/
  end

  test 'updates cash payment' do
    patch cash_payment_path(@payment), params: {
      cash_payment: {
        amount: 150.00,
        notes: 'Updated notes'
      }
    }
    assert_redirected_to cash_payment_path(@payment)
    @payment.reload
    assert_equal 150.00, @payment.amount.to_f
    assert_equal 'Updated notes', @payment.notes
  end

  test 'deletes cash payment' do
    assert_difference('CashPayment.count', -1) do
      delete cash_payment_path(@payment)
    end
    assert_redirected_to cash_payments_path
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
