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
      render :edit, status: :unprocessable_content
    end
  end

  private

  def membership_setting_params
    params.expect(membership_setting: %i[payment_grace_period_days reactivation_grace_period_months
                                         invitation_expiry_hours login_link_expiry_hours
                                         admin_login_link_expiry_minutes
                                         application_verification_expiry_hours
                                         manual_payment_due_soon_days])
  end
end
