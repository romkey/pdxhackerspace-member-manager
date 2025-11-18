class AddRechargeCustomerIdToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :recharge_customer_id, :string
    add_index :users, :recharge_customer_id
  end
end
