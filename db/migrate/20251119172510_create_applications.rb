class CreateApplications < ActiveRecord::Migration[7.1]
  def change
    create_table :applications do |t|
      t.string :name
      t.string :internal_url
      t.string :external_url
      t.string :authentik_prefix

      t.timestamps
    end
  end
end
