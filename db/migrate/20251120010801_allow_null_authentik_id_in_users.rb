class AllowNullAuthentikIdInUsers < ActiveRecord::Migration[7.1]
  def change
    change_column_null :users, :authentik_id, true
  end
end
