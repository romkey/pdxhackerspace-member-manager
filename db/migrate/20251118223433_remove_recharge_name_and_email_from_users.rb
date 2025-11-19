class RemoveRechargeNameAndEmailFromUsers < ActiveRecord::Migration[7.1]
  def change
    remove_column :users, :recharge_name, :string
    remove_column :users, :recharge_email, :string
  end
end
