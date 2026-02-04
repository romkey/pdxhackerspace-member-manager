class AddIndexToRechargePaymentsProcessedAt < ActiveRecord::Migration[7.1]
  def change
    # Add index on processed_at for efficient ordering
    add_index :recharge_payments, :processed_at, order: { processed_at: :desc }
    
    # Add customer_id column extracted from raw_attributes for efficient lookups
    add_column :recharge_payments, :customer_id, :string
    add_index :recharge_payments, :customer_id
    
    # Backfill customer_id from raw_attributes
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE recharge_payments 
          SET customer_id = COALESCE(
            raw_attributes->'customer'->>'id',
            raw_attributes->>'customer_id'
          )
          WHERE raw_attributes IS NOT NULL
        SQL
      end
    end
  end
end
