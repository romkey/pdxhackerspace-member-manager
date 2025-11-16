class AddUserToSlackUsers < ActiveRecord::Migration[7.1]
  def change
    add_reference :slack_users, :user, null: true, foreign_key: true
  end
end
