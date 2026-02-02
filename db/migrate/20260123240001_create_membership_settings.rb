class CreateMembershipSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :membership_settings do |t|
      t.integer :payment_grace_period_days, default: 14, null: false
      t.integer :reactivation_grace_period_months, default: 3, null: false
      t.timestamps
    end
  end
end
