class AddPronounsToSlackUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :slack_users, :pronouns, :string
  end
end
