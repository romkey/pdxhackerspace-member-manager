class AddSeenMemberHelpToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :seen_member_help, :boolean, default: false, null: false
  end
end
