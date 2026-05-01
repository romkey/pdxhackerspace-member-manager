require 'test_helper'

class AuthentikAutoSyncTest < ActiveJob::TestCase
  setup do
    Current.skip_authentik_sync = false
  end

  teardown do
    Current.skip_authentik_sync = nil
  end

  test 'user info change provisions authentik user when not yet linked' do
    user = users(:two)
    user.update_columns(authentik_id: nil)

    assert_enqueued_with(job: Authentik::ProvisionUserJob, args: [user.id]) do
      user.update!(full_name: 'Needs Authentik Provision')
    end
  end

  test 'manual application group membership change queues authentik membership sync' do
    group = application_groups(:sample_group)
    group.update_columns(authentik_group_id: 'authentik-group-123')
    user = users(:two)

    assert_enqueued_with(job: Authentik::ApplicationGroupMembershipSyncJob) do
      group.users << user unless group.users.include?(user)
    end
  end

  test 'provisioning a user queues application group membership sync after authentik id is assigned' do
    user = users(:two)
    user.update_columns(authentik_id: nil, username: 'provision-membership-sync')

    fake_client_class = Class.new do
      def find_user_by_username(_username)
        { 'pk' => 12_345 }
      end
    end

    original_client = Authentik.send(:remove_const, :Client)
    Authentik.const_set(:Client, fake_client_class)
    begin
      assert_enqueued_with(job: Authentik::ApplicationGroupMembershipSyncJob) do
        Authentik::ProvisionUserJob.perform_now(user.id)
      end
    ensure
      Authentik.send(:remove_const, :Client)
      Authentik.const_set(:Client, original_client)
    end

    assert_equal '12345', user.reload.authentik_id
  end
end
