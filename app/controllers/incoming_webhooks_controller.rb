# Admin interface for viewing and managing incoming webhook URL configurations.
class IncomingWebhooksController < AdminController
  before_action :set_incoming_webhook, only: %i[edit update]

  def index
    @incoming_webhooks = IncomingWebhook.order(:name)
    @base_url = ENV.fetch('MEMBER_MANAGER_BASE_URL', nil)
  end

  def edit
    @base_url = ENV.fetch('MEMBER_MANAGER_BASE_URL', nil)
  end

  def update
    if @incoming_webhook.update(incoming_webhook_params)
      redirect_to incoming_webhooks_path, notice: "'#{@incoming_webhook.name}' updated successfully."
    else
      @base_url = ENV.fetch('MEMBER_MANAGER_BASE_URL', nil)
      render :edit, status: :unprocessable_content
    end
  end

  # JSON endpoint for generating a random slug (used by the Randomize button)
  def random_slug
    render json: { slug: IncomingWebhook.generate_random_slug }
  end

  def seed
    IncomingWebhook.seed_defaults!
    redirect_to incoming_webhooks_path, notice: 'Incoming webhooks seeded successfully.'
  end

  private

  def set_incoming_webhook
    @incoming_webhook = IncomingWebhook.find(params[:id])
  end

  def incoming_webhook_params
    params.require(:incoming_webhook).permit(:slug, :description, :enabled)
  end
end
