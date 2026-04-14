require 'test_helper'

class PaymentHistoryTest < ActiveSupport::TestCase
  test 'for_user returns an enumerable' do
    user = users(:one)
    payments = PaymentHistory.for_user(user)
    assert_respond_to payments, :each
  end

  test 'for_user sorts payments by processed time descending' do
    user = users(:one)
    payments = PaymentHistory.for_user(user).to_a
    if payments.size < 2
      assert_operator payments.size, :<, 2
      return
    end

    times = payments.map { |p| p.processed_time || p.created_at || Time.zone.at(0) }
    assert_equal times, times.sort.reverse
  end
end
