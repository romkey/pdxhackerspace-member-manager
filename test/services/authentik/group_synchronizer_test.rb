require 'test_helper'

module Authentik
  class GroupSynchronizerTest < ActiveSupport::TestCase
    test 'records authentik users and links matching member without copying profile data' do
      user = users(:two)
      user.update_columns(
        authentik_id: nil,
        email: 'member-sync-authentik@example.com',
        full_name: 'Member Manager Name',
        username: 'membermanager',
        active: true,
        membership_status: 'paying',
        payment_type: 'paypal',
        authentik_attributes: {}
      )

      other_user = users(:one)
      other_user.update_columns(active: true)

      client = Class.new do
        attr_reader :requested_group_ids

        def initialize(members)
          @members = members
          @requested_group_ids = []
        end

        def group_members(group_id = nil)
          @requested_group_ids << group_id
          @members
        end
      end.new(
        [
          {
            authentik_id: '4242',
            email: user.email,
            full_name: 'Authentik Name',
            username: 'authentikusername',
            active: false,
            attributes: { 'rfid' => 'RFID-FROM-AUTHENTIK', 'department' => 'Ops' }
          }
        ]
      )

      Authentik::GroupSynchronizer.new(client: client).call

      authentik_user = AuthentikUser.find_by!(authentik_id: '4242')
      assert_equal user.id, authentik_user.user_id
      assert_equal 'Authentik Name', authentik_user.full_name
      assert_equal 'authentikusername', authentik_user.username

      user.reload
      assert_equal '4242', user.authentik_id
      assert_equal 'Member Manager Name', user.full_name
      assert_equal 'membermanager', user.username
      assert user.active?
      assert_equal 'paying', user.membership_status
      assert_equal 'paypal', user.payment_type
      assert_empty user.authentik_attributes
      assert_not Rfid.exists?(user: user, rfid: 'RFID-FROM-AUTHENTIK')

      assert other_user.reload.active?
    end

    test 'uses all members Authentik group as source when configured' do
      all_members_group = application_groups(:sample_group)
      all_members_group.update!(
        member_source: 'all_members',
        authentik_group_id: 'all-members-authentik-group'
      )

      client = Class.new do
        attr_reader :requested_group_ids

        def initialize
          @requested_group_ids = []
        end

        def group_members(group_id = nil)
          @requested_group_ids << group_id
          []
        end
      end.new

      Authentik::GroupSynchronizer.new(client: client).call

      assert_equal ['all-members-authentik-group'], client.requested_group_ids
    end
  end
end
