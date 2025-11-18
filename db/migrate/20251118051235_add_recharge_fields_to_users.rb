class AddRechargeFieldsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :recharge_name, :string
    add_column :users, :recharge_email, :string
    add_column :users, :recharge_order_number, :string
    add_column :users, :recharge_most_recent_payment_date, :datetime
  end
end
