require "google/apis/sheets_v4"
require "googleauth"

module GoogleSheets
  class Client
    MEMBER_LIST_TAB = "Member List".freeze
    ACCESS_TAB = "Access".freeze

    def initialize(spreadsheet_id: GoogleSheetsConfig.settings.spreadsheet_id, credentials_json: GoogleSheetsConfig.settings.credentials_json)
      @spreadsheet_id = spreadsheet_id
      @credentials_json = credentials_json
    end

    def fetch_sheet(tab_name)
      raise ArgumentError, "Google Sheets not configured" unless GoogleSheetsConfig.enabled?

      response = service.get_spreadsheet_values(@spreadsheet_id, tab_name)
      response.values || []
    end

    private

    def service
      @service ||= begin
        scope = ["https://www.googleapis.com/auth/spreadsheets.readonly"]
        authorizer = Google::Auth::ServiceAccountCredentials.make_creds(
          json_key_io: StringIO.new(@credentials_json),
          scope: scope
        )
        authorizer.fetch_access_token!

        service = Google::Apis::SheetsV4::SheetsService.new
        service.authorization = authorizer
        service
      end
    end
  end
end

