class AiOllamaProfilesController < AdminController
  before_action :set_ai_ollama_profile, only: %i[edit update]
  before_action :set_ai_providers, only: %i[edit update]

  def index
    @ai_ollama_profiles = AiOllamaProfile.ordered
  end

  def edit; end

  def update
    if @ai_ollama_profile.update(ai_ollama_profile_params)
      redirect_to ai_ollama_profiles_path, notice: "#{@ai_ollama_profile.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def check_health_now
    AiOllamaHealthCheckJob.perform_now
    redirect_to ai_ollama_profiles_path, notice: 'Health check finished.'
  end

  private

  def set_ai_ollama_profile
    @ai_ollama_profile = AiOllamaProfile.find(params[:id])
  end

  def ai_ollama_profile_params
    params.expect(
      ai_ollama_profile: %i[
        name
        ai_provider_id
        base_url
        api_key
        provider_name_override
        provider_url_override
        provider_api_key_override
        model
        prompt
        enabled
      ]
    )
  end

  def set_ai_providers
    @ai_provider_options = AiProvider.ordered.pluck(:name, :id)
  end
end
