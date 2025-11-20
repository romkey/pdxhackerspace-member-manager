class AddPaypalAccountIdToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :paypal_account_id, :string
    add_index :users, :paypal_account_id
  end
end
