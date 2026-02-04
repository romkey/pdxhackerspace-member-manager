class PaymentHistory
  def self.for_user(user)
    payments = []
    payments.concat(PaypalPayment.for_user(user).ordered.to_a)
    payments.concat(RechargePayment.for_user(user).ordered.to_a)
    sort_payments(payments)
  end

  def self.for_sheet_entry(sheet_entry)
    # Get payments via the user associated with this sheet entry
    return [] unless sheet_entry.user

    for_user(sheet_entry.user)
  end

  def self.sort_payments(payments)
    payments.sort_by { |payment| payment.processed_time || payment.created_at || Time.zone.at(0) }.reverse
  end
end
