class AddDontLinkToSlackUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :slack_users, :dont_link, :boolean, default: false, null: false
  end
end
