namespace :payment_events do
  desc 'Backfill payment events from existing PayPal, Recharge, KoFi, and Cash payments'
  task backfill: :environment do
    created = 0
    skipped = 0

    puts 'Backfilling PayPal payments...'
    PaypalPayment.find_each do |pp|
      if PaymentEvent.exists?(source: 'paypal', external_id: pp.paypal_id, event_type: 'payment')
        skipped += 1
        next
      end

      PaymentEvent.create!(
        user: pp.user,
        event_type: 'payment',
        source: 'paypal',
        amount: pp.amount,
        currency: pp.currency || 'USD',
        occurred_at: pp.transaction_time || pp.created_at,
        external_id: pp.paypal_id,
        details: "PayPal payment from #{pp.payer_name || pp.payer_email}",
        paypal_payment: pp
      )
      created += 1
    end
    puts "  PayPal: #{created} created, #{skipped} skipped"

    paypal_created = created
    created = 0
    skipped = 0

    puts 'Backfilling Recharge payments...'
    RechargePayment.find_each do |rp|
      if PaymentEvent.exists?(source: 'recharge', external_id: rp.recharge_id, event_type: 'payment')
        skipped += 1
        next
      end

      PaymentEvent.create!(
        user: rp.user,
        event_type: 'payment',
        source: 'recharge',
        amount: rp.amount,
        currency: rp.currency || 'USD',
        occurred_at: rp.processed_at || rp.created_at,
        external_id: rp.recharge_id,
        details: "Recharge payment from #{rp.customer_name || rp.customer_email}",
        recharge_payment: rp
      )
      created += 1
    end
    puts "  Recharge: #{created} created, #{skipped} skipped"

    recharge_created = created
    created = 0
    skipped = 0

    puts 'Backfilling Ko-Fi payments...'
    KofiPayment.find_each do |kp|
      if PaymentEvent.exists?(source: 'kofi', external_id: kp.kofi_transaction_id, event_type: 'payment')
        skipped += 1
        next
      end

      PaymentEvent.create!(
        user: kp.user,
        event_type: 'payment',
        source: 'kofi',
        amount: kp.amount,
        currency: kp.currency || 'USD',
        occurred_at: kp.timestamp || kp.created_at,
        external_id: kp.kofi_transaction_id,
        details: "Ko-Fi #{kp.payment_type || 'payment'} from #{kp.from_name || kp.email}",
        kofi_payment: kp
      )
      created += 1
    end
    puts "  Ko-Fi: #{created} created, #{skipped} skipped"

    kofi_created = created
    created = 0
    skipped = 0

    puts 'Backfilling Cash payments...'
    CashPayment.find_each do |cp|
      ext_id = "CASH-#{cp.id}"
      if PaymentEvent.exists?(source: 'cash', external_id: ext_id, event_type: 'payment')
        skipped += 1
        next
      end

      PaymentEvent.create!(
        user: cp.user,
        event_type: 'payment',
        source: 'cash',
        amount: cp.amount,
        currency: 'USD',
        occurred_at: cp.paid_on&.beginning_of_day || cp.created_at,
        external_id: ext_id,
        details: "Cash payment — #{cp.membership_plan&.name || 'Unknown plan'}",
        cash_payment: cp
      )
      created += 1
    end
    puts "  Cash: #{created} created, #{skipped} skipped"

    total = paypal_created + recharge_created + kofi_created + created
    puts "\nDone! #{total} payment events created total."
  end
end
