require 'test_helper'

module Slack
  class UserSynchronizerTest < ActiveSupport::TestCase
    test 'refreshes slack users and links matching member without copying profile data' do
      user = users(:two)
      user.update_columns(
        email: 'member-sync@example.com',
        aliases: [],
        slack_id: nil,
        slack_handle: nil,
        pronouns: nil,
        bio: nil,
        avatar: nil
      )

      client = Class.new do
        def initialize(users)
          @users = users
        end

        def list_users
          @users
        end
      end.new(
        [
          {
            slack_id: 'U-MEMBER-SYNC',
            team_id: 'T123',
            username: 'slackmember',
            real_name: user.full_name,
            display_name: 'Slack Member',
            email: user.email,
            pronouns: 'they/them',
            title: 'Slack title',
            is_bot: false,
            deleted: false,
            raw_attributes: {
              'profile' => { 'image_original' => 'yes', 'image_192' => 'https://example.com/avatar.png' }
            },
            last_synced_at: Time.current
          }
        ]
      )

      Slack::UserSynchronizer.new(client: client).call

      slack_user = SlackUser.find_by!(slack_id: 'U-MEMBER-SYNC')
      assert_equal user.id, slack_user.user_id

      user.reload
      assert_nil user.slack_id
      assert_nil user.slack_handle
      assert_nil user.pronouns
      assert_nil user.bio
      assert_nil user.avatar
      assert_empty user.aliases
    end
  end
end
