class AddVerbsToAccessControllerTypes < ActiveRecord::Migration[7.1]
  def change
    add_column :access_controller_types, :verbs, :jsonb, null: false, default: []
  end
end
