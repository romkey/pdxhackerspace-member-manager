class AddGreetingNameToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :greeting_name, :string
    add_column :users, :use_full_name_for_greeting, :boolean, default: true, null: false
    add_column :users, :use_username_for_greeting, :boolean, default: false, null: false
  end
end
