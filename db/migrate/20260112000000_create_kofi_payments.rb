class CreateKofiPayments < ActiveRecord::Migration[7.1]
  def change
    create_table :kofi_payments do |t|
      t.string :kofi_transaction_id, null: false
      t.string :message_id
      t.string :status
      t.decimal :amount, precision: 12, scale: 2
      t.string :currency
      t.datetime :timestamp
      t.string :payment_type
      t.string :from_name
      t.string :email
      t.text :message
      t.string :url
      t.boolean :is_public, default: false
      t.boolean :is_subscription_payment, default: false
      t.boolean :is_first_subscription_payment, default: false
      t.string :tier_name
      t.jsonb :shop_items, default: []
      t.jsonb :raw_attributes, default: {}, null: false
      t.datetime :last_synced_at
      t.references :user, foreign_key: true
      t.references :sheet_entry, foreign_key: true

      t.timestamps
    end

    add_index :kofi_payments, :kofi_transaction_id, unique: true
    add_index :kofi_payments, :email
    add_index :kofi_payments, :message_id
  end
end
