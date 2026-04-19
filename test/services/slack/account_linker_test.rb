# frozen_string_literal: true

require 'test_helper'

module Slack
  class AccountLinkerTest < ActiveSupport::TestCase
    setup do
      @cfg = Rails.application.config.x.slack_oidc
      @prev = {
        client_id: @cfg.client_id,
        client_secret: @cfg.client_secret,
        team_id: @cfg.team_id
      }
      @cfg.client_id = 'test_client'
      @cfg.client_secret = 'test_secret'
      @cfg.team_id = 'T123'
    end

    teardown do
      @cfg.client_id = @prev[:client_id]
      @cfg.client_secret = @prev[:client_secret]
      @cfg.team_id = @prev[:team_id]
    end

    test 'links unlinked SlackUser to user when team and sub match' do
      user = users(:member_with_local_account)
      su = slack_users(:with_dept)
      su.update_columns(user_id: nil)

      result = AccountLinker.call(
        user: user,
        id_token_payload: {
          'sub' => su.slack_id,
          'https://slack.com/team_id' => 'T123'
        }
      )

      assert result.success?
      assert_equal user.id, su.reload.user_id
    end

    test 'fails when workspace team does not match' do
      user = users(:member_with_local_account)
      su = slack_users(:with_dept)
      su.update_columns(user_id: nil)

      result = AccountLinker.call(
        user: user,
        id_token_payload: {
          'sub' => su.slack_id,
          'https://slack.com/team_id' => 'T999'
        }
      )

      assert result.failure?
      assert_nil su.reload.user_id
    end

    test 'fails when Slack user is already linked to another member' do
      user = users(:member_with_local_account)
      other = users(:two)
      su = slack_users(:with_dept)
      su.update!(user_id: other.id)

      result = AccountLinker.call(
        user: user,
        id_token_payload: {
          'sub' => su.slack_id,
          'https://slack.com/team_id' => 'T123'
        }
      )

      assert result.failure?
      assert_equal other.id, su.reload.user_id
    end
  end
end
