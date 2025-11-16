class UsersController < AuthenticatedController
  def index
    @users = User.ordered_by_display_name
    @user_count = @users.count
    @active_count = @users.where(active: true).count
    @inactive_count = @user_count - @active_count
  end

  def show
    @user = User.find(params[:id])
    @payments = PaymentHistory.for_user(@user)
    @journals = @user.journals.includes(:actor_user).order(changed_at: :desc, created_at: :desc)
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    # Update standard fields first
    if @user.update(user_params)
      # Merge notes into authentik_attributes if provided
      notes = params.dig(:user, :notes).to_s
      if notes.present?
        attrs = (@user.authentik_attributes || {}).dup
        attrs["notes"] = notes
        @user.update_column(:authentik_attributes, attrs)
      end
      redirect_to user_path(@user), notice: "User updated successfully."
    else
      flash.now[:alert] = "Unable to update user."
      render :edit, status: :unprocessable_content
    end
  end

  def sync
    Authentik::GroupSyncJob.perform_later
    redirect_to users_path, notice: "Authentik group sync has been scheduled."
  end

  private

  def user_params
    params.require(:user).permit(:full_name, :email, :active)
  end
end
