class AiOllamaHealthCheckJob < ApplicationJob
  queue_as :default

  def perform
    AiOllamaProfile.ordered.each do |profile|
      check_profile(profile)
    end
  end

  private

  def check_profile(profile)
    unless profile.enabled?
      profile.update_columns(
        last_health_check_at: Time.current,
        updated_at: Time.current
      )
      return
    end

    url = profile.effective_base_url
    if url.blank?
      profile.record_not_configured!
      return
    end

    result = Ollama::HealthCheck.call(base_url: url, api_key: profile.effective_api_key)
    if result.ok
      profile.record_health_success!
    else
      profile.record_health_failure!(result.error)
    end
  end
end
