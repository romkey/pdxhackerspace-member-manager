class CreatePaypalPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :paypal_payments do |t|
      t.string :paypal_id, null: false
      t.string :status
      t.decimal :amount, precision: 12, scale: 2
      t.string :currency
      t.datetime :transaction_time
      t.string :transaction_type
      t.string :payer_email
      t.string :payer_name
      t.string :payer_id
      t.jsonb :raw_attributes, null: false, default: {}
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :paypal_payments, :paypal_id, unique: true
  end
end

