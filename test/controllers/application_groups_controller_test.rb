require 'test_helper'

class ApplicationGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @application = applications(:sample_app)
    @application_group = application_groups(:sample_group)
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'should get show' do
    get application_application_group_url(@application, @application_group)
    assert_response :success
  end

  test 'should get new' do
    get new_application_application_group_url(@application)
    assert_response :success
  end

  test 'should get edit' do
    get edit_application_application_group_url(@application, @application_group)
    assert_response :success
  end

  test 'should create application group with manual members' do
    assert_difference('ApplicationGroup.count', 1) do
      post application_application_groups_url(@application), params: {
        application_group: {
          name: 'New Manual Group',
          authentik_name: 'test:new-manual',
          member_source: 'manual'
        }
      }
    end
    group = ApplicationGroup.last
    assert_equal 'manual', group.member_source
    assert_redirected_to application_application_group_url(@application, group)
  end

  test 'should create application group with active members' do
    assert_difference('ApplicationGroup.count', 1) do
      post application_application_groups_url(@application), params: {
        application_group: {
          name: 'Active Group',
          authentik_name: 'test:active',
          member_source: 'active_members'
        }
      }
    end
    group = ApplicationGroup.last
    assert_equal 'active_members', group.member_source
  end

  test 'should create group syncing with another group via combined select' do
    assert_difference('ApplicationGroup.count', 1) do
      post application_application_groups_url(@application), params: {
        application_group: {
          name: 'Synced Group',
          authentik_name: 'test:synced',
          member_source: 'sync_group',
          sync_group_combined: "sync_group:#{@application_group.id}",
          sync_with_group_id: @application_group.id
        }
      }
    end
    group = ApplicationGroup.last
    assert_equal 'sync_group', group.member_source
    assert_equal @application_group.id, group.sync_with_group_id
  end

  test 'should resolve active_members from sync_group combined select' do
    assert_difference('ApplicationGroup.count', 1) do
      post application_application_groups_url(@application), params: {
        application_group: {
          name: 'Active via Sync',
          authentik_name: 'test:active-via-sync',
          member_source: 'sync_group',
          sync_group_combined: 'active_members'
        }
      }
    end
    group = ApplicationGroup.last
    assert_equal 'active_members', group.member_source
    assert_nil group.sync_with_group_id
  end

  test 'should update application group' do
    patch application_application_group_url(@application, @application_group), params: {
      application_group: { name: 'Updated Group', member_source: 'manual' }
    }
    assert_response :redirect
    @application_group.reload
    assert_equal 'Updated Group', @application_group.name
  end

  test 'should add user to manual group' do
    user = users(:one)
    post add_user_application_application_group_url(@application, @application_group), params: {
      user_id: user.id
    }
    assert_response :redirect
  end

  test 'should not add user to non-manual group' do
    @application_group.update!(member_source: 'active_members')
    user = users(:one)
    post add_user_application_application_group_url(@application, @application_group), params: {
      user_id: user.id
    }
    assert_response :redirect
    assert_match(/Cannot add members/, flash[:alert])
  end

  test 'should remove user' do
    user = users(:one)
    @application_group.users << user unless @application_group.users.include?(user)
    delete remove_user_application_application_group_url(@application, @application_group), params: {
      user_id: user.id
    }
    assert_response :redirect
  end

  test 'should destroy application group' do
    assert_difference('ApplicationGroup.count', -1) do
      delete application_application_group_url(@application, @application_group)
    end
    assert_redirected_to application_url(@application)
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
