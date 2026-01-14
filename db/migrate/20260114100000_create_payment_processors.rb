class CreatePaymentProcessors < ActiveRecord::Migration[7.1]
  def change
    create_table :payment_processors do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.boolean :enabled, default: true, null: false
      t.integer :display_order, default: 0

      # Sync tracking
      t.datetime :last_sync_at
      t.datetime :last_successful_sync_at
      t.string :last_error_message
      t.integer :consecutive_error_count, default: 0
      t.string :sync_status, default: 'unknown'

      # Statistics
      t.integer :total_payments_count, default: 0
      t.integer :matched_payments_count, default: 0
      t.integer :unmatched_payments_count, default: 0
      t.decimal :total_amount, precision: 12, scale: 2, default: 0
      t.decimal :amount_last_30_days, precision: 12, scale: 2, default: 0
      t.decimal :average_payment_amount, precision: 12, scale: 2, default: 0

      # Configuration status
      t.boolean :api_configured, default: false
      t.boolean :webhook_configured, default: false
      t.string :webhook_url
      t.datetime :webhook_last_received_at

      # Import history
      t.datetime :last_csv_import_at
      t.integer :csv_import_count, default: 0

      # Admin notes
      t.text :notes

      t.timestamps
    end

    add_index :payment_processors, :key, unique: true
    add_index :payment_processors, :enabled
    add_index :payment_processors, :display_order
  end
end
