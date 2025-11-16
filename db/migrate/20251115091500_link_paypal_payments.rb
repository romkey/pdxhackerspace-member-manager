class LinkPaypalPayments < ActiveRecord::Migration[7.1]
  def change
    add_reference :paypal_payments, :user, foreign_key: true
    add_reference :paypal_payments, :sheet_entry, foreign_key: true
    add_index :paypal_payments, :payer_email
  end
end

