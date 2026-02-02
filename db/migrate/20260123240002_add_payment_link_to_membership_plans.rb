class AddPaymentLinkToMembershipPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :membership_plans, :payment_link, :string
  end
end
