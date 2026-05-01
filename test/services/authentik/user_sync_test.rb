require 'test_helper'

module Authentik
  class UserSyncTest < ActiveSupport::TestCase
    setup do
      @settings = AuthentikConfig.settings
      @original_api_token = @settings.api_token
      @original_api_base_url = @settings.api_base_url
      @settings.api_token = 'test-token'
      @settings.api_base_url = 'https://authentik.example.test'
    end

    teardown do
      @settings.api_token = @original_api_token
      @settings.api_base_url = @original_api_base_url
    end

    test 'sync_from_authentik records external data without copying fields to user' do
      user = users(:two)
      user.update_columns(
        authentik_id: 'authentik-sync-from-test',
        email: 'membermanager@example.com',
        full_name: 'Member Manager Name',
        username: 'membermanager'
      )

      client = Class.new do
        def get_user(_authentik_id)
          {
            'username' => 'authentikusername',
            'email' => 'authentik@example.com',
            'name' => 'Authentik Name',
            'is_active' => true
          }
        end
      end.new

      result = Authentik::UserSync.new(user, client: client).sync_from_authentik!

      assert_equal 'updated', result[:status]
      authentik_user = AuthentikUser.find_by!(authentik_id: user.authentik_id)
      assert_equal user.id, authentik_user.user_id
      assert_equal 'authentik@example.com', authentik_user.email
      assert_equal 'Authentik Name', authentik_user.full_name
      assert_equal 'authentikusername', authentik_user.username

      user.reload
      assert_equal 'membermanager@example.com', user.email
      assert_equal 'Member Manager Name', user.full_name
      assert_equal 'membermanager', user.username
    end
  end
end
