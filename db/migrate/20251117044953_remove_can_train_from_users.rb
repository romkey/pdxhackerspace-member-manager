class RemoveCanTrainFromUsers < ActiveRecord::Migration[7.1]
  def change
    remove_column :users, :can_train, :string
  end
end
