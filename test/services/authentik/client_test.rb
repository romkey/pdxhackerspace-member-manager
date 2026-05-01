require 'test_helper'

module Authentik
  class ClientTest < ActiveSupport::TestCase
    test 'normalize_member reads nested user object fields' do
      client = Authentik::Client.new(base_url: 'https://authentik.example.test', token: 'test-token')

      member = client.send(:normalize_member, {
                             'pk' => 'membership-row',
                             'is_active' => true,
                             'user_obj' => {
                               'pk' => 123,
                               'email' => 'user@example.com',
                               'name' => 'Nested User',
                               'username' => 'nesteduser'
                             }
                           })

      assert_equal '123', member[:authentik_id]
      assert_equal 'user@example.com', member[:email]
      assert_equal 'Nested User', member[:full_name]
      assert_equal 'nesteduser', member[:username]
      assert member[:active]
    end

    test 'normalize_member hydrates incomplete identity fields from user endpoint' do
      client = Authentik::Client.new(base_url: 'https://authentik.example.test', token: 'test-token')
      requested_ids = []

      client.define_singleton_method(:get_user) do |authentik_id|
        requested_ids << authentik_id.to_s
        {
          'pk' => 123,
          'email' => 'hydrated@example.com',
          'name' => 'Hydrated User',
          'username' => 'hydrateduser',
          'is_active' => true
        }
      end

      member = client.send(:normalize_member, {
                             'pk' => 123,
                             'name' => 'Partial User',
                             'is_active' => true
                           })

      assert_equal '123', member[:authentik_id]
      assert_equal 'hydrated@example.com', member[:email]
      assert_equal 'Hydrated User', member[:full_name]
      assert_equal 'hydrateduser', member[:username]
      assert_equal ['123'], requested_ids
    end
  end
end
