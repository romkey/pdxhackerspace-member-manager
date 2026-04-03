require 'test_helper'

class AiOllamaProfileTest < ActiveSupport::TestCase
  test 'effective_base_url falls back to default for non-default keys' do
    default = ai_ollama_profiles(:default)
    default.update!(base_url: 'http://ollama.test:11434')

    app_status = ai_ollama_profiles(:application_status)
    app_status.update!(base_url: '')
    assert_equal 'http://ollama.test:11434', app_status.effective_base_url
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
