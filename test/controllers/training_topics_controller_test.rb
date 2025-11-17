require "test_helper"

class TrainingTopicsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get training_topics_index_url
    assert_response :success
  end

  test "should get new" do
    get training_topics_new_url
    assert_response :success
  end

  test "should get create" do
    get training_topics_create_url
    assert_response :success
  end

  test "should get destroy" do
    get training_topics_destroy_url
    assert_response :success
  end
end
