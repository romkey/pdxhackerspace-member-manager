class AddUserIdToMembershipPlans < ActiveRecord::Migration[8.0]
  def change
    add_reference :membership_plans, :user, foreign_key: true, null: true

    remove_index :membership_plans, :name
    add_index :membership_plans, :name, unique: true, where: "user_id IS NULL",
              name: "index_membership_plans_on_name_shared"
  end
end
