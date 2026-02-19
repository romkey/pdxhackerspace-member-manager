require 'test_helper'

class PaymentHistoryTest < ActiveSupport::TestCase
  test 'for_user includes cash payments' do
    user = users(:cash_payer)
    payments = PaymentHistory.for_user(user)
    cash_payments_found = payments.select { |p| p.is_a?(CashPayment) }
    assert cash_payments_found.any?, 'PaymentHistory should include cash payments'
  end

  test 'for_user sorts payments by processed time descending' do
    user = users(:one)
    payments = PaymentHistory.for_user(user)
    next if payments.size < 2

    times = payments.map { |p| p.processed_time || p.created_at || Time.zone.at(0) }
    assert_equal times, times.sort.reverse
  end
end
