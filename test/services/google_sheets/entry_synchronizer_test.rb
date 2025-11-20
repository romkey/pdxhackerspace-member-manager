require 'test_helper'
require 'minitest/mock'

module GoogleSheets
  class EntrySynchronizerTest < ActiveSupport::TestCase
    setup do
      @client = Minitest::Mock.new
      @client.expect(:fetch_sheet, member_rows, [GoogleSheets::Client::MEMBER_LIST_TAB])
      @client.expect(:fetch_sheet, access_rows, [GoogleSheets::Client::ACCESS_TAB])
      GoogleSheetsConfig.stub(:enabled?, true) do
        EntrySynchronizer.new(client: @client).call
      end
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
