class RemoveSheetIdFromPayments < ActiveRecord::Migration[7.1]
  def change
    remove_reference :paypal_payments, :sheet_entry, index: true, foreign_key: false
    remove_reference :recharge_payments, :sheet_entry, index: true, foreign_key: false
  end
end
