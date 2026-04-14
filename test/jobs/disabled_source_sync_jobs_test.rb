require 'test_helper'

class DisabledSourceSyncJobsTest < ActiveJob::TestCase
  # ─── Authentik::GroupSyncJob ────────────────────────────────────

  test 'Authentik::GroupSyncJob skips when authentik source is disabled' do
    member_sources(:authentik).update!(enabled: false)

    assert_nil Authentik::GroupSyncJob.perform_now
  end

  # ─── GoogleSheets::SyncJob ─────────────────────────────────────

  test 'GoogleSheets::SyncJob skips when sheet source is disabled' do
    member_sources(:sheet).update!(enabled: false)

    assert_nil GoogleSheets::SyncJob.perform_now
  end

  # ─── Slack::UserSyncJob ────────────────────────────────────────

  test 'Slack::UserSyncJob skips when slack source is disabled' do
    member_sources(:slack).update!(enabled: false)

    assert_nil Slack::UserSyncJob.perform_now
  end

  # ─── Authentik::FullSyncToAuthentikJob ─────────────────────────

  test 'Authentik::FullSyncToAuthentikJob skips when member_manager source is disabled' do
    member_sources(:member_manager).update!(enabled: false)

    assert_nil Authentik::FullSyncToAuthentikJob.perform_now
  end

  # ─── Authentik::ApplicationGroupMembershipSyncJob ──────────────

  test 'Authentik::ApplicationGroupMembershipSyncJob skips when member_manager source is disabled' do
    member_sources(:member_manager).update!(enabled: false)

    assert_nil Authentik::ApplicationGroupMembershipSyncJob.perform_now(%w[sheet slack])
  end
end
