class AuthentikWebhooksController < AdminController
  def index
    @webhook_setup = Authentik::WebhookSetup.new
    begin
      @status = @webhook_setup.status
    rescue Faraday::ForbiddenError
      @status = { configured: false, error: 'Authentik API returned 403 Forbidden. The API token may lack permissions or have expired.' }
    rescue Faraday::Error => e
      @status = { configured: false, error: "Authentik API error: #{e.message}" }
    end
    @synced_groups = ApplicationGroup.with_authentik_group_id.includes(:application).order('applications.name', :name)
    @member_manager_base_url = ENV['MEMBER_MANAGER_BASE_URL']
  end

  def setup
    setup = Authentik::WebhookSetup.new
    result = setup.setup!

    if result[:success]
      redirect_to authentik_webhooks_path, notice: 'Webhook configuration created successfully.'
    else
      redirect_to authentik_webhooks_path, alert: "Setup failed: #{result[:error]}"
    end
  end

  def teardown
    setup = Authentik::WebhookSetup.new
    result = setup.teardown!

    if result[:success]
      redirect_to authentik_webhooks_path, notice: 'Webhook configuration removed successfully.'
    else
      redirect_to authentik_webhooks_path, alert: "Teardown failed: #{result[:error]}"
    end
  end
end
