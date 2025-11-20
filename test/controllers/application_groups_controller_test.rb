require 'test_helper'

class ApplicationGroupsControllerTest < ActionDispatch::IntegrationTest
  test 'should get show' do
    get application_groups_show_url
    assert_response :success
  end

  test 'should get edit' do
    get application_groups_edit_url
    assert_response :success
  end

  test 'should get update' do
    get application_groups_update_url
    assert_response :success
  end

  test 'should get add_user' do
    get application_groups_add_user_url
    assert_response :success
  end

  test 'should get remove_user' do
    get application_groups_remove_user_url
    assert_response :success
  end
end
