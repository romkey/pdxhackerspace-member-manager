require 'test_helper'

module GoogleSheets
  class EntrySynchronizerTest < ActiveSupport::TestCase
    setup do
      @google_sheets_settings = GoogleSheetsConfig.settings
      @original_credentials_json = @google_sheets_settings.credentials_json
      @original_spreadsheet_id = @google_sheets_settings.spreadsheet_id
      @google_sheets_settings.credentials_json = '{"type":"service_account"}'
      @google_sheets_settings.spreadsheet_id = 'test-sheet-id'

      @client = Class.new do
        def initialize(member_rows:, access_rows:)
          @member_rows = member_rows
          @access_rows = access_rows
        end

        def fetch_sheet(tab_name)
          case tab_name
          when GoogleSheets::Client::MEMBER_LIST_TAB
            @member_rows
          when GoogleSheets::Client::ACCESS_TAB
            @access_rows
          else
            raise ArgumentError, "Unexpected tab: #{tab_name}"
          end
        end
      end.new(member_rows: member_rows, access_rows: access_rows)
      EntrySynchronizer.new(client: @client).call
    end

    teardown do
      @google_sheets_settings.credentials_json = @original_credentials_json
      @google_sheets_settings.spreadsheet_id = @original_spreadsheet_id
    end

    test 'merges member and access data' do
      entry = SheetEntry.find_by(email: 'example@example.com')
      assert entry
      assert_equal 'Sample Name', entry.name
      assert_equal 'Yes', entry.rfid
      assert_equal 'Owner', entry.status
    end

    private

    def member_rows
      [
        ['name', 'dirty', 'status', 'twitter', 'alias', 'email', 'date added', 'payment', 'paypal name', 'notes'],
        ['Sample Name', '', 'Owner', '', '', 'example@example.com', '2024-01-01', 'Stripe', '', '']
      ]
    end

    def access_rows
      [
        ['name', 'dirty', 'status', 'rfid', 'laser', 'sewing machine'],
        ['Sample Name', '', 'Owner', 'Yes', 'No', 'Yes']
      ]
    end
  end
end
