require 'test_helper'

class RagControllerTest < ActionDispatch::IntegrationTest
  test 'responds without authentication' do
    get '/rag.json'
    assert_response :success
  end

  test 'returns JSON content type' do
    get '/rag.json'
    assert_equal 'application/json; charset=utf-8', response.content_type
  end

  test 'includes interests key with array of names' do
    get '/rag.json'
    body = response.parsed_body
    assert body.key?('interests'), 'response should have interests key'
    assert_kind_of Array, body['interests']
  end

  test 'includes training_topics key with array of names' do
    get '/rag.json'
    body = response.parsed_body
    assert body.key?('training_topics'), 'response should have training_topics key'
    assert_kind_of Array, body['training_topics']
  end

  test 'interests contains fixture interest names' do
    get '/rag.json'
    body = response.parsed_body
    assert_includes body['interests'], interests(:electronics).name
    assert_includes body['interests'], interests(:woodworking).name
  end

  test 'interests are in alphabetical order' do
    get '/rag.json'
    names = response.parsed_body['interests']
    assert_equal names, names.sort
  end

  test 'training_topics contains fixture topic names' do
    get '/rag.json'
    body = response.parsed_body
    assert_includes body['training_topics'], training_topics(:laser_cutting).name
    assert_includes body['training_topics'], training_topics(:woodworking).name
  end

  test 'training_topics are in alphabetical order' do
    get '/rag.json'
    names = response.parsed_body['training_topics']
    assert_equal names, names.sort
  end

  test 'response contains only interests and training_topics keys' do
    get '/rag.json'
    body = response.parsed_body
    assert_equal %w[interests training_topics], body.keys.sort
  end

  test 'values are plain strings with no nested objects' do
    get '/rag.json'
    body = response.parsed_body
    body['interests'].each { |v| assert_kind_of String, v }
    body['training_topics'].each { |v| assert_kind_of String, v }
  end
end
