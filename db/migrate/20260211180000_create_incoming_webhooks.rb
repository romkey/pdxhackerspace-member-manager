class CreateIncomingWebhooks < ActiveRecord::Migration[7.1]
  def change
    create_table :incoming_webhooks do |t|
      t.string :name, null: false
      t.string :webhook_type, null: false
      t.string :slug, null: false
      t.boolean :enabled, default: true, null: false
      t.text :description

      t.timestamps
    end

    add_index :incoming_webhooks, :webhook_type, unique: true
    add_index :incoming_webhooks, :slug, unique: true
  end
end
