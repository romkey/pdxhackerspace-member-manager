# frozen_string_literal: true

require 'test_helper'

class SlackAccountLinksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
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
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
    @cfg.client_id = @prev[:client_id]
    @cfg.client_secret = @prev[:client_secret]
    @cfg.team_id = @prev[:team_id]
  end

  test 'new redirects to Slack authorize URL when signed in' do
    sign_in_local_member
    get slack_link_start_path
    assert_response :redirect
    assert_match %r{\Ahttps://slack\.com/openid/connect/authorize}, @response.redirect_url
    assert_match 'client_id=test_client', @response.redirect_url
    assert_match 'scope=openid', @response.redirect_url
  end

  test 'new redirects to login when not signed in' do
    get slack_link_start_path
    assert_redirected_to login_path
  end

  test 'callback shows error when state does not match session' do
    sign_in_local_member
    get slack_link_callback_path(code: 'abc', state: 'wrong')
    assert_redirected_to user_path(users(:member_with_local_account), tab: :dashboard)
    assert_match 'Invalid or expired', flash[:alert].to_s
  end

  private

  def sign_in_local_member
    post local_login_path, params: {
      session: {
        email: 'member@example.com',
        password: 'memberpassword123'
      }
    }
  end
end
