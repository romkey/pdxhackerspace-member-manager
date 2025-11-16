class PaymentHistory
  def self.for_user(user)
    payments = []
    payments.concat(PaypalPayment.for_user(user).ordered.to_a)
    payments.concat(RechargePayment.for_user(user).ordered.to_a)
    sort_payments(payments)
  end

  def self.for_sheet_entry(sheet_entry)
    payments = []
    payments.concat(PaypalPayment.for_sheet_entry(sheet_entry).ordered.to_a)
    payments.concat(RechargePayment.for_sheet_entry(sheet_entry).ordered.to_a)
    sort_payments(payments)
  end

  def self.sort_payments(payments)
    payments.sort_by { |payment| payment.processed_time || payment.created_at || Time.at(0) }.reverse
  end
end

