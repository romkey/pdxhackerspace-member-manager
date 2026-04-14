require 'test_helper'

class AiOllamaProfileTest < ActiveSupport::TestCase
  test 'effective_base_url falls back to default for non-default keys' do
    default = ai_ollama_profiles(:default)
    default.update!(base_url: 'http://ollama.test:11434')

    app_status = ai_ollama_profiles(:application_status)
    app_status.update!(base_url: '')
    assert_equal 'http://ollama.test:11434', app_status.effective_base_url
  end

  test 'effective_model falls back to default for non-default keys' do
    default = ai_ollama_profiles(:default)
    default.update!(model: 'llama3.2')

    app_status = ai_ollama_profiles(:application_status)
    app_status.update!(model: '')
    assert_equal 'llama3.2', app_status.effective_model
  end

  test 'effective_base_url uses provider URL when selected' do
    profile = ai_ollama_profiles(:application_status)
    profile.update!(base_url: '', ai_provider: ai_providers(:claude))

    assert_equal 'https://api.anthropic.com', profile.effective_base_url
  end

  test 'effective_base_url uses override before provider URL' do
    profile = ai_ollama_profiles(:application_status)
    profile.update!(
      ai_provider: ai_providers(:claude),
      provider_url_override: 'https://override.example.com'
    )

    assert_equal 'https://override.example.com', profile.effective_base_url
  end

  test 'effective_api_key resolves override provider service then default' do
    default = ai_ollama_profiles(:default)
    default.update!(api_key: 'default-key')

    profile = ai_ollama_profiles(:application_status)
    profile.update!(api_key: 'service-key')
    assert_equal 'service-key', profile.effective_api_key

    profile.update!(api_key: '', ai_provider: ai_providers(:claude))
    assert_equal 'claude-key', profile.effective_api_key

    profile.update!(provider_api_key_override: 'override-key')
    assert_equal 'override-key', profile.effective_api_key
  end

  test 'urgent_health_issue when enabled, has url, unhealthy' do
    p = ai_ollama_profiles(:default)
    p.update!(enabled: true, base_url: 'http://x.test', health_status: 'unhealthy')
    assert p.urgent_health_issue?
  end

  test 'not urgent when disabled even if unhealthy' do
    p = ai_ollama_profiles(:default)
    p.update!(enabled: false, base_url: 'http://x.test', health_status: 'unhealthy')
    assert_not p.urgent_health_issue?
  end

  test 'not urgent when unconfigured' do
    p = ai_ollama_profiles(:default)
    p.update!(enabled: true, base_url: '', health_status: 'not_configured')
    assert_not p.urgent_health_issue?
  end
end
