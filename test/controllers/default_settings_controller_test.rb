require "test_helper"

class DefaultSettingsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get default_settings_index_url
    assert_response :success
  end

  test "should get edit" do
    get default_settings_edit_url
    assert_response :success
  end

  test "should get update" do
    get default_settings_update_url
    assert_response :success
  end
end
