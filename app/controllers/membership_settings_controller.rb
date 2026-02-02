class MembershipSettingsController < AdminController
  def show
    @membership_setting = MembershipSetting.instance
  end

  def edit
    @membership_setting = MembershipSetting.instance
  end

  def update
    @membership_setting = MembershipSetting.instance

    if @membership_setting.update(membership_setting_params)
      redirect_to membership_settings_path, notice: 'Membership settings updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def membership_setting_params
    params.require(:membership_setting).permit(:payment_grace_period_days, :reactivation_grace_period_months)
  end
end
