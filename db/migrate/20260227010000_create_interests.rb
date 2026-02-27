class CreateInterests < ActiveRecord::Migration[7.1]
  def change
    create_table :interests do |t|
      t.string :name, null: false
      t.timestamps
    end

    add_index :interests, :name, unique: true

    create_table :user_interests do |t|
      t.references :user,     null: false, foreign_key: true
      t.references :interest, null: false, foreign_key: true
      t.timestamps
    end

    add_index :user_interests, [:user_id, :interest_id], unique: true
  end
end
