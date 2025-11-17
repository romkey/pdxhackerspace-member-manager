class AddCanTrainAndSignNameToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :can_train, :string, array: true, default: []
    add_column :users, :sign_name, :string, null: true
  end
end
