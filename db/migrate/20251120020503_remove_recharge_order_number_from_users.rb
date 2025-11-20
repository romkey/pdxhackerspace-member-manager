class RemoveRechargeOrderNumberFromUsers < ActiveRecord::Migration[7.1]
  def change
    remove_column :users, :recharge_order_number, :string
  end
end
