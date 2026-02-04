class AddDontLinkToPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :paypal_payments, :dont_link, :boolean, default: false, null: false
    add_column :recharge_payments, :dont_link, :boolean, default: false, null: false
  end
end
