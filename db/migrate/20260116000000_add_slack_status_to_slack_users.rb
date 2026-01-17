class AddSlackStatusToSlackUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :slack_users, :slack_status, :boolean, null: false, default: false
  end
end
