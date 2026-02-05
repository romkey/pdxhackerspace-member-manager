class AddMembershipEndedDateToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :membership_ended_date, :date
  end
end
