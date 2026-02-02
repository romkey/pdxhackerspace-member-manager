class AddPronounsToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :pronouns, :string
  end
end
