# Admin interface for viewing and managing incoming webhook URL configurations.
class IncomingWebhooksController < AdminController
  before_action :set_incoming_webhook, only: %i[edit update regenerate_slug]

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

  def regenerate_slug
    custom_slug = params[:custom_slug].presence
    error = validate_custom_slug(custom_slug) if custom_slug
    return redirect_with_slug_error(error) if error

    @incoming_webhook.regenerate_slug!(custom_slug)
    redirect_to edit_incoming_webhook_path(@incoming_webhook),
                notice: "Webhook URL for '#{@incoming_webhook.name}' has been regenerated."
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
    params.require(:incoming_webhook).permit(:description, :enabled)
  end

  def validate_custom_slug(slug)
    unless slug.match?(IncomingWebhook::SLUG_FORMAT)
      return 'Invalid slug format. Only letters, numbers, hyphens, and underscores.'
    end

    if IncomingWebhook.where.not(id: @incoming_webhook.id).exists?(slug: slug)
      return 'That slug is already in use by another webhook.'
    end

    nil
  end

  def redirect_with_slug_error(error)
    redirect_to edit_incoming_webhook_path(@incoming_webhook), alert: error
  end
end
