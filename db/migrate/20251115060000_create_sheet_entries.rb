class CreateSheetEntries < ActiveRecord::Migration[7.1]
  def change
    create_table :sheet_entries do |t|
      t.string :name, null: false
      t.string :dirty
      t.string :status
      t.string :twitter
      t.string :alias_name
      t.string :email
      t.datetime :date_added
      t.string :payment
      t.string :paypal_name
      t.text :notes

      t.string :rfid
      t.string :laser
      t.string :sewing_machine
      t.string :serger
      t.string :embroidery_machine
      t.string :dremel
      t.string :ender
      t.string :prusa
      t.string :laminator
      t.string :shaper
      t.string :general_shop
      t.string :event_host
      t.string :vinyl_cutter
      t.string :mpcnc_marlin
      t.string :longmill

      t.jsonb :raw_attributes, null: false, default: {}
      t.datetime :last_synced_at

      t.timestamps
    end

    add_index :sheet_entries, :email
    add_index :sheet_entries, :name
  end
end

