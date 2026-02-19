class CreateCashPayments < ActiveRecord::Migration[8.0]
  def change
    create_table :cash_payments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :membership_plan, null: false, foreign_key: true
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.date :paid_on, null: false
      t.text :notes
      t.references :recorded_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :cash_payments, :paid_on, order: :desc
  end
end
