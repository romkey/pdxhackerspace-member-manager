class AddLastActiveAtToSlackUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :slack_users, :last_active_at, :datetime
  end
end
