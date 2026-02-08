class AddManualAndVisibleToMembershipPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :membership_plans, :manual, :boolean, null: false, default: false
    add_column :membership_plans, :visible, :boolean, null: false, default: true
    add_index :membership_plans, :manual
    add_index :membership_plans, :visible
  end
end
