class AuthentikWebhooksController < AdminController
  def index
    @webhook_setup = Authentik::WebhookSetup.new
    @status = @webhook_setup.status
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
