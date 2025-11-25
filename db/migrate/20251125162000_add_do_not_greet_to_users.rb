class AddDoNotGreetToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :do_not_greet, :boolean, default: false, null: false
  end
end

