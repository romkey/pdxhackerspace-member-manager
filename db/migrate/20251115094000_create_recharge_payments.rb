class CreateRechargePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :recharge_payments do |t|
      t.string :recharge_id, null: false
      t.string :status
      t.decimal :amount, precision: 12, scale: 2
      t.string :currency
      t.datetime :processed_at
      t.string :charge_type
      t.string :customer_email
      t.string :customer_name
      t.jsonb :raw_attributes, null: false, default: {}
      t.datetime :last_synced_at
      t.references :user, foreign_key: true
      t.references :sheet_entry, foreign_key: true

      t.timestamps
    end

    add_index :recharge_payments, :recharge_id, unique: true
    add_index :recharge_payments, :customer_email
  end
end

