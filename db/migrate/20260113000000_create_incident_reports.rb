class CreateIncidentReports < ActiveRecord::Migration[7.1]
  def change
    create_table :incident_reports do |t|
      t.date :incident_date, null: false
      t.string :subject, null: false
      t.string :incident_type, null: false
      t.string :other_type_explanation
      t.text :description
      t.references :reporter, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    # Join table for incident reports and involved members
    create_table :incident_report_members do |t|
      t.references :incident_report, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :incident_report_members, [:incident_report_id, :user_id], unique: true, name: 'idx_incident_report_members_unique'
    add_index :incident_reports, :incident_date
    add_index :incident_reports, :incident_type
  end
end
