class UsersController < AuthenticatedController
  def index
    @users = User.ordered_by_display_name
    @user_count = @users.count
    @active_count = @users.where(membership_status: "active").count
    @inactive_count = @user_count - @active_count
  end

  def show
    @user = User.includes(:sheet_entry, :rfids, trainings_as_trainee: :training_topic, training_topics: []).find(params[:id])
    @payments = PaymentHistory.for_user(@user)
    @journals = @user.journals.includes(:actor_user).order(changed_at: :desc, created_at: :desc)
    @most_recent_access = @user.access_logs.order(logged_at: :desc).first
    @recent_accesses = @user.access_logs.order(logged_at: :desc).limit(10)
    
    # Find previous and next users using the same ordering as index
    ordered_ids = User.ordered_by_display_name.pluck(:id)
    current_index = ordered_ids.index(@user.id)
    
    if current_index
      @previous_user = current_index > 0 ? User.find(ordered_ids[current_index - 1]) : nil
      @next_user = current_index < ordered_ids.length - 1 ? User.find(ordered_ids[current_index + 1]) : nil
    else
      @previous_user = nil
      @next_user = nil
    end
  end

  def edit
    @user = User.find(params[:id])
  end

  def update
    @user = User.find(params[:id])
    
    # Parse RFID from textarea (one per line only, not comma-separated)
    rfid_text = params.dig(:user, :rfid).to_s
    rfid_array = rfid_text.split(/\n/).map(&:strip).reject(&:blank?)
    
    # Update user with parsed RFID
    user_attrs = user_params.merge(rfid: rfid_array)
    
    if @user.update(user_attrs)
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
    params.require(:user).permit(:full_name, :email, :membership_status, :payment_type, :notes)
  end
end
