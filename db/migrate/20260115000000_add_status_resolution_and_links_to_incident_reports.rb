class AddStatusResolutionAndLinksToIncidentReports < ActiveRecord::Migration[7.1]
  def change
    # Add status and resolution to incident_reports
    add_column :incident_reports, :status, :string, default: 'draft', null: false
    add_column :incident_reports, :resolution, :text
    add_index :incident_reports, :status

    # Create links table
    create_table :incident_report_links do |t|
      t.references :incident_report, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      t.integer :position, default: 0

      t.timestamps
    end

    add_index :incident_report_links, [:incident_report_id, :position]
  end
end
