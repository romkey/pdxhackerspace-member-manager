require 'test_helper'

class AiOllamaProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @original_local_auth_enabled = Rails.application.config.x.local_auth.enabled
    Rails.application.config.x.local_auth.enabled = true
    sign_in_as_admin
  end

  teardown do
    Rails.application.config.x.local_auth.enabled = @original_local_auth_enabled
  end

  test 'should get index' do
    get ai_ollama_profiles_url
    assert_response :success
  end

  test 'should get edit' do
    profile = ai_ollama_profiles(:default)
    get edit_ai_ollama_profile_url(profile)
    assert_response :success
  end

  test 'should update profile' do
    profile = ai_ollama_profiles(:default)
    patch ai_ollama_profile_url(profile), params: {
      ai_ollama_profile: {
        name: 'Default Ollama',
        base_url: 'http://127.0.0.1:11434',
        model: 'llama3.2',
        prompt: 'You are helpful.',
        enabled: '1'
      }
    }
    assert_redirected_to ai_ollama_profiles_url
    profile.reload
    assert_equal 'Default Ollama', profile.name
    assert_equal 'http://127.0.0.1:11434', profile.base_url
    assert_equal 'llama3.2', profile.model
  end

  test 'check_health_now runs job and redirects' do
    ok_result = Ollama::HealthCheck::Result.new(ok: true, error: nil)
    Ollama::HealthCheck.stub(:call, ok_result) do
      post check_health_now_ai_ollama_profiles_url
    end
    assert_redirected_to ai_ollama_profiles_url
  end

  private

  def sign_in_as_admin
    account = local_accounts(:active_admin)
    post local_login_path, params: {
      session: { email: account.email, password: 'localpassword123' }
    }
  end
end
