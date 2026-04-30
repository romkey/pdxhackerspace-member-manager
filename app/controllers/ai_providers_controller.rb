class AiProvidersController < AdminController
  before_action :set_ai_provider, only: %i[edit update destroy]

  def index
    @ai_providers = AiProvider.ordered
  end

  def new
    @ai_provider = AiProvider.new
  end

  def edit; end

  def create
    @ai_provider = AiProvider.new(ai_provider_params)
    if @ai_provider.save
      redirect_to ai_providers_path, notice: 'AI provider created successfully.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @ai_provider.update(ai_provider_params)
      redirect_to ai_providers_path, notice: 'AI provider updated successfully.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @ai_provider.destroy!
    redirect_to ai_providers_path, notice: 'AI provider deleted.'
  end

  private

  def set_ai_provider
    @ai_provider = AiProvider.find(params[:id])
  end

  def ai_provider_params
    permitted = params.expect(ai_provider: %i[name url api_key])
    permitted.delete(:api_key) if permitted[:api_key].blank?
    permitted
  end
end
