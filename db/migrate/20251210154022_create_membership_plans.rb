class CreateMembershipPlans < ActiveRecord::Migration[7.1]
  def change
    create_table :membership_plans do |t|
      t.string :name, null: false
      t.decimal :cost, precision: 10, scale: 2, null: false
      t.string :billing_frequency, null: false
      t.text :description

      t.timestamps
    end
    
    add_index :membership_plans, :name, unique: true
  end
end
