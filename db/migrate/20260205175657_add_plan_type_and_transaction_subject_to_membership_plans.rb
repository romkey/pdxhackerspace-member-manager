class AddPlanTypeAndTransactionSubjectToMembershipPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :membership_plans, :plan_type, :string, default: 'primary', null: false
    add_column :membership_plans, :paypal_transaction_subject, :string
    add_index :membership_plans, :plan_type
  end
end
