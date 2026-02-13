class IncomingWebhooksController < AdminController
  before_action :set_incoming_webhook, only: [:regenerate_slug]

  def index
    @incoming_webhooks = IncomingWebhook.order(:name)
    @base_url = ENV['MEMBER_MANAGER_BASE_URL']
  end

  def regenerate_slug
    custom_slug = params[:custom_slug].presence

    if custom_slug
      # Validate the custom slug format
      unless custom_slug.match?(/\A[a-zA-Z0-9_-]+\z/)
        redirect_to incoming_webhooks_path, alert: "Invalid slug format. Only letters, numbers, hyphens, and underscores are allowed."
        return
      end

      # Check uniqueness
      if IncomingWebhook.where.not(id: @incoming_webhook.id).exists?(slug: custom_slug)
        redirect_to incoming_webhooks_path, alert: "That slug is already in use by another webhook."
        return
      end

      @incoming_webhook.regenerate_slug!(custom_slug)
    else
      @incoming_webhook.regenerate_slug!
    end

    redirect_to incoming_webhooks_path, notice: "Webhook URL for '#{@incoming_webhook.name}' has been regenerated."
  end

  def seed
    IncomingWebhook.seed_defaults!
    redirect_to incoming_webhooks_path, notice: "Incoming webhooks seeded successfully."
  end

  private

  def set_incoming_webhook
    @incoming_webhook = IncomingWebhook.find(params[:id])
  end
end
