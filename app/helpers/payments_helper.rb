module PaymentsHelper
  def payment_identifier(payment)
    payment.respond_to?(:identifier) ? payment.identifier : payment.id
  end

  def payment_status(payment)
    payment.respond_to?(:status) ? payment.status : 'Unknown'
  end

  def payment_amount(payment)
    if payment.respond_to?(:amount_with_currency)
      payment.amount_with_currency
    elsif payment.respond_to?(:amount)
      payment.amount
    end
  end

  def payment_processed_time(payment)
    if payment.respond_to?(:processed_time)
      payment.processed_time
    elsif payment.respond_to?(:processed_at)
      payment.processed_at
    end
  end

  def payment_show_path(payment)
    case payment
    when PaypalPayment
      paypal_payment_path(payment)
    when RechargePayment
      recharge_payment_path(payment)
    when KofiPayment
      kofi_payment_path(payment)
    else
      '#'
    end
  end

  def payment_source_label(payment)
    case payment
    when PaypalPayment
      'PayPal'
    when RechargePayment
      'Recharge'
    when KofiPayment
      'Ko-Fi'
    else
      'Payment'
    end
  end

  def payment_type_badge_class(payment_type)
    case payment_type.to_s.downcase
    when 'donation'
      'primary'
    when 'subscription', 'membership'
      'success'
    when 'commission'
      'warning'
    when 'shop order', 'shop_order'
      'info'
    else
      'secondary'
    end
  end
end
