class DefaultSettingsController < AdminController
  def show
    @default_setting = DefaultSetting.instance
  end

  def edit
    @default_setting = DefaultSetting.instance
  end

  def provision_core_groups
    provisioner = Authentik::CoreGroupProvisioner.new
    results = provisioner.provision_and_sync!

    parts = []
    parts << "Created: #{results[:created].join(', ')}" if results[:created].any?
    parts << "Already existed: #{results[:existing].count}" if results[:existing].any?
    parts << "Synced: #{results[:synced].count}" if results[:synced].any?
    parts << "Errors: #{results[:errors].join('; ')}" if results[:errors].any?

    notice = "Core groups provisioned. #{parts.join('. ')}."
    redirect_to default_settings_path, notice: notice
  end

  def update
    @default_setting = DefaultSetting.instance

    if @default_setting.update(default_setting_params)
      redirect_to default_settings_path, notice: 'Default settings updated successfully.'
    else
      flash.now[:alert] = 'Unable to update default settings.'
      render :edit, status: :unprocessable_content
    end
  end

  private

  def default_setting_params
    params.require(:default_setting).permit(:site_prefix, :app_prefix, :members_prefix, :active_members_group, :admins_group, :unbanned_members_group, :all_members_group, :trained_on_prefix, :can_train_prefix, :sync_inactive_members)
  end
end
