class CreateMembershipApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :membership_applications do |t|
      t.string :email, null: false
      t.string :status, null: false, default: 'draft'
      t.string :token, null: false
      t.datetime :submitted_at
      t.references :reviewed_by, foreign_key: { to_table: :users }, null: true
      t.datetime :reviewed_at
      t.text :admin_notes

      t.timestamps
    end

    add_index :membership_applications, :token, unique: true
    add_index :membership_applications, :status
    add_index :membership_applications, :email
  end
end
