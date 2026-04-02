class AddDuesDueAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :dues_due_at, :datetime

    User.reset_column_information

    say_with_time 'Backfilling users.dues_due_at from billing cycles' do
      User.find_each do |user|
        next if user.membership_status.in?(%w[guest sponsored])

        anchor = backfill_most_recent_payment_date(user)
        plan = user.membership_plan
        next if anchor.blank? || plan.blank?

        at = backfill_dues_due_at(anchor, plan)
        user.update_column(:dues_due_at, at) if at
      end
    end
  end

  def down
    remove_column :users, :dues_due_at
  end

  private

  def backfill_most_recent_payment_date(user)
    dates = []
    dates << user.last_payment_date if user.last_payment_date.present?
    dates << user.recharge_most_recent_payment_date.to_date if user.recharge_most_recent_payment_date.present?
    if user.paypal_payments.respond_to?(:maximum)
      t = user.paypal_payments.where.not(transaction_time: nil).maximum(:transaction_time)
      dates << t.to_date if t.present?
    end
    if user.recharge_payments.respond_to?(:maximum)
      t = user.recharge_payments.where.not(processed_at: nil).maximum(:processed_at)
      dates << t.to_date if t.present?
    end
    cash_max = user.cash_payments.maximum(:paid_on)
    dates << cash_max if cash_max.present?
    dates.compact.max
  end

  def backfill_dues_due_at(anchor_date, plan)
    d = case plan.billing_frequency
        when 'monthly' then anchor_date.to_date + 1.month
        when 'yearly' then anchor_date.to_date + 1.year
        when 'one-time' then nil
        end
    d&.in_time_zone&.beginning_of_day
  end
end
