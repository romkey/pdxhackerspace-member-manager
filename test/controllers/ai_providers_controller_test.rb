require 'test_helper'

class AiProvidersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
    @ai_provider = ai_providers(:claude)
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'should get index' do
    get ai_providers_url
    assert_response :success
  end

  test 'should get new' do
    get new_ai_provider_url
    assert_response :success
  end

  test 'should create provider' do
    assert_difference 'AiProvider.count' do
      post ai_providers_url, params: {
        ai_provider: {
          name: 'Perplexity',
          url: 'https://api.perplexity.ai',
          api_key: 'secret'
        }
      }
    end

    assert_redirected_to ai_providers_url
  end

  test 'should get edit' do
    get edit_ai_provider_url(@ai_provider)
    assert_response :success
  end

  test 'should update provider' do
    patch ai_provider_url(@ai_provider), params: {
      ai_provider: {
        name: 'Claude 3',
        url: 'https://api.anthropic.com/v1',
        api_key: 'new-key'
      }
    }

    assert_redirected_to ai_providers_url
    @ai_provider.reload
    assert_equal 'Claude 3', @ai_provider.name
    assert_equal 'https://api.anthropic.com/v1', @ai_provider.url
  end

  test 'should destroy provider' do
    assert_difference 'AiProvider.count', -1 do
      delete ai_provider_url(@ai_provider)
    end

    assert_redirected_to ai_providers_url
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
