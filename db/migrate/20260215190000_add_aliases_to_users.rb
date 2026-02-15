class AddAliasesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :aliases, :string, array: true, default: [], null: false
  end
end
