class AddManualPaymentDueSoonDaysToMembershipSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :membership_settings, :manual_payment_due_soon_days, :integer, default: 7, null: false
  end
end
