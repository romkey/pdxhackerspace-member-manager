Rails.application.config.x.google_sheets = ActiveSupport::InheritableOptions.new(
  credentials_json: ENV["GOOGLE_SHEETS_CREDENTIALS"],
  spreadsheet_id: ENV["GOOGLE_SHEETS_ID"]
)

module GoogleSheetsConfig
  def self.settings
    Rails.application.config.x.google_sheets
  end

  def self.enabled?
    settings.credentials_json.present? && settings.spreadsheet_id.present?
  end
end

