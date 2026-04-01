require 'test_helper'

class AccessLogParserTest < ActiveSupport::TestCase
  # Pattern 1 line shape: "... host accesscontrol[N]: <name> has <action> <location>"

  test 'create_access_log! links member when parsed name is one word and matches full_name exactly' do
    user = User.create!(
      authentik_id: 'access-log-parser-oneword',
      email: 'oneword-accesslog@example.com',
      full_name: 'Madonna',
      active: true
    )

    line = 'Nov 15 14:41:35 unit2 accesscontrol[2113]: Madonna has opened unit2 front door'

    assert_difference 'AccessLog.count', 1 do
      AccessLogParser.new(line, file_year: 2025).create_access_log!
    end

    log = AccessLog.order(:id).last
    assert_equal user.id, log.user_id
    assert_equal 'Madonna', log.name
  end

  test 'create_access_log! does not link when one word is only a prefix of full_name' do
    user = users(:one)
    assert_equal 'Example User One', user.full_name

    line = 'Nov 15 14:41:35 unit2 accesscontrol[2113]: Example has opened unit2 front door'

    assert_difference 'AccessLog.count', 1 do
      AccessLogParser.new(line, file_year: 2025).create_access_log!
    end

    log = AccessLog.order(:id).last
    assert_nil log.user_id
    assert_equal 'Example', log.name
  end
end
