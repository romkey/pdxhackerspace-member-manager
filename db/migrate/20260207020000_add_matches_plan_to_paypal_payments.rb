class AddMatchesPlanToPaypalPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :paypal_payments, :matches_plan, :boolean, null: false, default: true
    add_index :paypal_payments, :matches_plan

    # Mark all existing payments as matching a plan (they were filtered on import)
    reversible do |dir|
      dir.up do
        execute "UPDATE paypal_payments SET matches_plan = true"
      end
    end
  end
end
