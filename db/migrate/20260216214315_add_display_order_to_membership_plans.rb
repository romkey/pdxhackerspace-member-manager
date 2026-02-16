class AddDisplayOrderToMembershipPlans < ActiveRecord::Migration[8.1]
  def change
    add_column :membership_plans, :display_order, :integer, default: 1, null: false
    add_index :membership_plans, :display_order
  end
end
