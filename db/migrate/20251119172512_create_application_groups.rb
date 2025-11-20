class CreateApplicationGroups < ActiveRecord::Migration[7.1]
  def change
    create_table :application_groups do |t|
      t.references :application, null: false, foreign_key: true
      t.string :name
      t.string :authentik_name
      t.text :note

      t.timestamps
    end
  end
end
