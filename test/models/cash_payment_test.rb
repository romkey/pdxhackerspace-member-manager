require 'test_helper'

class CashPaymentTest < ActiveSupport::TestCase
  test 'valid cash payment saves successfully' do
    payment = build_cash_payment
    assert payment.valid?, payment.errors.full_messages.join(', ')
  end

  test 'requires amount greater than zero' do
    payment = build_cash_payment(amount: 0)
    assert_not payment.valid?
    assert payment.errors.key?(:amount)
  end

  test 'requires amount to be present' do
    payment = build_cash_payment(amount: nil)
    assert_not payment.valid?
    assert payment.errors.key?(:amount)
  end

  test 'requires paid_on to be present' do
    payment = build_cash_payment(paid_on: nil)
    assert_not payment.valid?
    assert payment.errors.key?(:paid_on)
  end

  test 'requires membership plan to be personal' do
    shared_plan = membership_plans(:monthly_standard)
    payment = build_cash_payment(membership_plan: shared_plan)
    assert_not payment.valid?
    assert payment.errors.key?(:membership_plan)
  end

  test 'allows personal membership plan' do
    payment = build_cash_payment
    assert payment.valid?
  end

  test 'identifier returns CASH- prefixed id' do
    payment = cash_payments(:sample_cash_payment)
    assert_equal "CASH-#{payment.id}", payment.identifier
  end

  test 'processed_time returns paid_on as beginning of day' do
    payment = build_cash_payment(paid_on: Date.new(2026, 2, 1))
    assert_equal Date.new(2026, 2, 1).beginning_of_day, payment.processed_time
  end

  test 'amount_with_currency formats correctly' do
    payment = build_cash_payment(amount: 100.50)
    assert_equal '100.50 USD', payment.amount_with_currency
  end

  test 'status returns completed' do
    payment = build_cash_payment
    assert_equal 'completed', payment.status
  end

  test 'for_user scope returns payments for given user' do
    user = users(:cash_payer)
    payments = CashPayment.for_user(user)
    assert(payments.all? { |p| p.user_id == user.id })
  end

  test 'ordered scope sorts by paid_on descending' do
    payments = CashPayment.ordered
    dates = payments.map(&:paid_on)
    assert_equal dates.sort.reverse, dates
  end

  private

  def build_cash_payment(attrs = {})
    defaults = {
      user: users(:cash_payer),
      membership_plan: membership_plans(:personal_equipment_donation),
      amount: 100.00,
      paid_on: Date.current,
      notes: 'Test payment'
    }
    CashPayment.new(defaults.merge(attrs))
  end
end
