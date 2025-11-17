class AddPaymentTypeToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :payment_type, :string, default: "unknown"
  end
end
