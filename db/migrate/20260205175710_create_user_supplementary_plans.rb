class CreateUserSupplementaryPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :user_supplementary_plans do |t|
      t.references :user, null: false, foreign_key: true
      t.references :membership_plan, null: false, foreign_key: true

      t.timestamps
    end
    add_index :user_supplementary_plans, [:user_id, :membership_plan_id], unique: true, name: 'index_user_supplementary_plans_unique'
  end
end
