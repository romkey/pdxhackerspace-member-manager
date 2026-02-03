class AddMembershipStartDateToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :membership_start_date, :date
  end
end
