class CreateLocalAccounts < ActiveRecord::Migration[7.1]
  def change
    create_table :local_accounts do |t|
      t.string :email, null: false
      t.string :full_name
      t.string :password_digest, null: false
      t.boolean :active, default: true, null: false
      t.boolean :admin, default: false, null: false
      t.datetime :last_signed_in_at

      t.timestamps
    end
    add_index :local_accounts, :email, unique: true
  end
end
