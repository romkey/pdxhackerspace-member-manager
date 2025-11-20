require 'test_helper'
require 'active_job/test_helper'

class SheetEntriesControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @sheet_entry = sheet_entries(:member_list_entry)
    @local_account = local_accounts(:active_admin)
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    log_in_local_user
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'shows index' do
    get sheet_entries_path
    assert_response :success
    assert_select 'h1', text: 'Sheet Entries'
    assert_match @sheet_entry.name, response.body
    assert_match(/share Authentik emails/, response.body)
    assert_match(/share Authentik names/, response.body)
  end

  test 'shows a single entry' do
    get sheet_entry_path(@sheet_entry)
    assert_response :success
    assert_match @sheet_entry.name, response.body
    assert_match @sheet_entry.status, response.body
    assert_match @sheet_entry.paypal_payments.first.paypal_id, response.body
    assert_match @sheet_entry.recharge_payments.first.recharge_id, response.body
  end

  test 'enqueues sync job' do
    assert_enqueued_with(job: GoogleSheets::SyncJob) do
      post sync_sheet_entries_path
    end
    assert_redirected_to sheet_entries_path
  end

  private

  def log_in_local_user
    post local_login_path, params: {
      session: {
        email: @local_account.email,
        password: 'localpassword123'
      }
    }
    follow_redirect!
  end
end
