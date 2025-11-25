class UsersController < AuthenticatedController
  before_action :set_user_for_show, only: [:show]
  before_action :set_user, only: [:edit, :update, :activate, :deactivate, :ban, :mark_deceased, :destroy]
  before_action :require_admin!, except: [:show, :edit, :update]
  before_action :authorize_self_or_admin, only: [:show, :edit, :update]

  def index
    @users = User.ordered_by_display_name

    # Apply search filter if provided
    if params[:q].present?
      search_term = "%#{params[:q].downcase}%"
      @users = @users.where(
        "LOWER(COALESCE(full_name, '')) LIKE :p OR LOWER(COALESCE(email, '')) LIKE :p OR LOWER(authentik_id) LIKE :p OR LOWER(COALESCE(username, '')) LIKE :p",
        p: search_term
      )
    end

    @user_count = @users.count
    @active_count = @users.where(active: true).count
    @inactive_count = @user_count - @active_count

    # Membership status counts
    @membership_status_unknown = @users.where(membership_status: 'unknown').count
    @membership_status_sponsored = @users.where(membership_status: 'sponsored').count
    @membership_status_basic = @users.where(membership_status: 'basic').count
    @membership_status_banned = @users.where(membership_status: 'banned').count
    @membership_status_deceased = @users.where(membership_status: 'deceased').count

    # Payment type counts
    @payment_type_unknown = @users.where(payment_type: 'unknown').count
    @payment_type_sponsored = @users.where(payment_type: 'sponsored').count
    @payment_type_paypal = @users.where(payment_type: 'paypal').count
    @payment_type_recharge = @users.where(payment_type: 'recharge').count
    @payment_type_cash = @users.where(payment_type: 'cash').count

    # Dues status counts
    @dues_status_current = @users.where(dues_status: 'current').count
    @dues_status_lapsed = @users.where(dues_status: 'lapsed').count
    @dues_status_inactive = @users.where(dues_status: 'inactive').count
    @dues_status_unknown = @users.where(dues_status: 'unknown').count
  end

  def show
    return unless current_user_admin?

    @payments = PaymentHistory.for_user(@user)
    @journals = @user.journals.includes(:actor_user).order(changed_at: :desc, created_at: :desc)
    @most_recent_access = @user.access_logs.order(logged_at: :desc).first
    @recent_accesses = @user.access_logs.order(logged_at: :desc).limit(10)

    # Find previous and next users using the same ordering as index
    ordered_ids = User.ordered_by_display_name.pluck(:id)
    current_index = ordered_ids.index(@user.id)

    if current_index
      @previous_user = current_index.positive? ? User.find(ordered_ids[current_index - 1]) : nil
      @next_user = current_index < ordered_ids.length - 1 ? User.find(ordered_ids[current_index + 1]) : nil
    else
      @previous_user = nil
      @next_user = nil
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to user_path(@user), notice: 'User updated successfully.'
    else
      flash.now[:alert] = 'Unable to update user.'
      render :edit, status: :unprocessable_content
    end
  end

  def sync
    Authentik::GroupSyncJob.perform_later
    redirect_to users_path, notice: 'Authentik group sync has been scheduled.'
  end

  def activate
    @user.update!(active: true)
    redirect_to user_path(@user), notice: 'User activated.'
  end

  def deactivate
    @user.update!(active: false)
    redirect_to user_path(@user), notice: 'User deactivated.'
  end

  def ban
    @user.update!(membership_status: 'banned', active: false)
    redirect_to user_path(@user), notice: 'User banned.'
  end

  def mark_deceased
    @user.update!(membership_status: 'deceased', active: false)
    redirect_to user_path(@user), notice: 'User marked as deceased.'
  end

  def destroy
    @user.destroy!
    redirect_to users_path, notice: 'User deleted successfully.'
  end

  private

  def set_user_for_show
    @user = User.includes(:sheet_entry, :slack_user, :rfids, trainings_as_trainee: :training_topic,
                           training_topics: []).find(params[:id])
  end

  def set_user
    @user = User.find(params[:id])
  end

  def authorize_self_or_admin
    return if current_user_admin?
    return if @user == current_user

    redirect_to user_path(current_user), alert: 'You may only view and edit your own profile.'
  end

  def user_params
    permitted = %i[
      username full_name email greeting_name use_full_name_for_greeting
      use_username_for_greeting do_not_greet
    ]

    if current_user_admin?
      permitted += %i[membership_status payment_type notes active]
      permitted << :is_admin
    end

    params.require(:user).permit(permitted)
  end
end
