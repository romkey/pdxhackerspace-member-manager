class CreateUserLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :user_links do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      t.integer :position, default: 0

      t.timestamps
    end

    add_index :user_links, [:user_id, :position]
  end
end
