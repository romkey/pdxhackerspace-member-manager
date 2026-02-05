class UsersController < AuthenticatedController
  skip_before_action :require_authenticated_user!, only: [:show]
  before_action :set_user_for_show, only: [:show]
  before_action :set_user, only: [:edit, :update, :activate, :deactivate, :ban, :mark_deceased, :destroy, :sync_to_authentik, :sync_from_authentik, :mark_help_seen]
  before_action :require_admin!, except: [:show, :edit, :update, :mark_help_seen]
  before_action :authorize_profile_view, only: [:show]
  before_action :authorize_self_or_admin, only: [:edit, :update]

  SORTABLE_COLUMNS = %w[username full_name email membership_status payment_type last_synced_at].freeze

  def index
    # Start with all users for counts (before filtering)
    all_users = User.all

    # Calculate counts from ALL users (not filtered)
    @user_count = all_users.count
    @active_count = all_users.where(active: true).count
    @inactive_count = @user_count - @active_count

    # Membership status counts (from all users)
    @membership_status_unknown = all_users.where(membership_status: 'unknown').count
    @membership_status_sponsored = all_users.where(membership_status: 'sponsored').count
    @membership_status_paying = all_users.where(membership_status: 'paying').count
    @membership_status_banned = all_users.where(membership_status: 'banned').count
    @membership_status_deceased = all_users.where(membership_status: 'deceased').count
    @membership_status_applicant = all_users.where(membership_status: 'applicant').count

    # Payment type counts (from all users)
    @payment_type_unknown = all_users.where(payment_type: 'unknown').count
    @payment_type_sponsored = all_users.where(payment_type: 'sponsored').count
    @payment_type_paypal = all_users.where(payment_type: 'paypal').count
    @payment_type_recharge = all_users.where(payment_type: 'recharge').count
    @payment_type_cash = all_users.where(payment_type: 'cash').count

    # Dues status counts (from all users)
    @dues_status_current = all_users.where(dues_status: 'current').count
    @dues_status_lapsed = all_users.where(dues_status: 'lapsed').count
    @dues_status_inactive = all_users.where(dues_status: 'inactive').count
    @dues_status_unknown = all_users.where(dues_status: 'unknown').count

    # Missing data counts (from all users)
    @no_rfid_count = all_users.left_joins(:rfids).where(rfids: { id: nil }).count
    @no_email_count = all_users.where("email IS NULL OR email = ''").count

    # Now build filtered query
    @users = all_users

    # Apply search filter if provided
    if params[:q].present?
      search_term = "%#{params[:q].downcase}%"
      @users = @users.where(
        "LOWER(COALESCE(full_name, '')) LIKE :p OR LOWER(COALESCE(email, '')) LIKE :p OR LOWER(authentik_id) LIKE :p OR LOWER(COALESCE(username, '')) LIKE :p",
        p: search_term
      )
    end

    # Apply status filters
    @users = @users.where(membership_status: params[:membership_status]) if params[:membership_status].present?
    @users = @users.where(payment_type: params[:payment_type]) if params[:payment_type].present?
    @users = @users.where(dues_status: params[:dues_status]) if params[:dues_status].present?
    @users = @users.where(active: params[:active] == 'true') if params[:active].present?
    
    # Apply missing data filters
    if params[:missing] == 'rfid'
      @users = @users.left_joins(:rfids).where(rfids: { id: nil })
    elsif params[:missing] == 'email'
      @users = @users.where("email IS NULL OR email = ''")
    end

    # Apply sorting
    @sort_column = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : 'full_name'
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
    @users = @users.order("#{@sort_column} #{@sort_direction} NULLS LAST")

    # Track if any filter is active
    @filter_active = params[:membership_status].present? || params[:payment_type].present? || 
                     params[:dues_status].present? || params[:active].present? || params[:missing].present?
    @filtered_count = @users.count if @filter_active

    # Store filter/sort params for passing to user profile links
    @list_params = {}
    @list_params[:membership_status] = params[:membership_status] if params[:membership_status].present?
    @list_params[:payment_type] = params[:payment_type] if params[:payment_type].present?
    @list_params[:dues_status] = params[:dues_status] if params[:dues_status].present?
    @list_params[:active] = params[:active] if params[:active].present?
    @list_params[:missing] = params[:missing] if params[:missing].present?
    @list_params[:sort] = params[:sort] if params[:sort].present?
    @list_params[:direction] = params[:direction] if params[:direction].present?
  end

  def show
    # Determine view level based on viewer and profile settings
    @natural_view_level = determine_view_level
    @view_level = determine_effective_view_level

    # Set up view preview options for admins and profile owners
    setup_view_preview_options

    # Default tab
    @active_tab = params[:tab]&.to_sym || :profile

    # Load payment history for admin and self views (paginated)
    if @view_level == :admin || @view_level == :self
      payments_query = PaymentHistory.for_user(@user)
      @payments_count = payments_query.count
      @pagy_payments, @payments = pagy_array(payments_query.to_a, limit: 20, page_param: :payments_page)
    end

    # Admin-only data (true admins, even when impersonating)
    if true_user_admin?
      # Journals (paginated) - only load for admin view
      if @view_level == :admin
        journals_query = @user.journals.includes(:actor_user).order(changed_at: :desc, created_at: :desc)
        @journals_count = journals_query.count
        @pagy_journals, @journals = pagy(journals_query, limit: 20, page_param: :journal_page)

        # Access logs (paginated)
        access_query = @user.access_logs.order(logged_at: :desc)
        @access_count = access_query.count
        @most_recent_access = access_query.first
        @pagy_accesses, @recent_accesses = pagy(access_query, limit: 20, page_param: :access_page)

        # Incidents (paginated)
        incidents_query = @user.incident_reports.includes(:reporter).ordered
        @incidents_count = incidents_query.count
        @pagy_incidents, @user_incidents = pagy(incidents_query, limit: 20, page_param: :incidents_page)
      end

      # Find previous and next users for navigation (always for admin toolbar)
      # Rebuild the same filtered/sorted query from the index page
      nav_query = User.all

      # Apply filters if present
      nav_query = nav_query.where(membership_status: params[:membership_status]) if params[:membership_status].present?
      nav_query = nav_query.where(payment_type: params[:payment_type]) if params[:payment_type].present?
      nav_query = nav_query.where(dues_status: params[:dues_status]) if params[:dues_status].present?
      nav_query = nav_query.where(active: params[:active] == 'true') if params[:active].present?

      # Apply sorting
      sort_column = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : 'full_name'
      sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
      nav_query = nav_query.order("#{sort_column} #{sort_direction} NULLS LAST")

      ordered_ids = nav_query.pluck(:id)
      current_index = ordered_ids.index(@user.id)

      if current_index
        @previous_user = current_index.positive? ? User.find(ordered_ids[current_index - 1]) : nil
        @next_user = current_index < ordered_ids.length - 1 ? User.find(ordered_ids[current_index + 1]) : nil
      else
        @previous_user = nil
        @next_user = nil
      end

      # Store filter/sort params for use in view links
      @nav_params = {}
      @nav_params[:membership_status] = params[:membership_status] if params[:membership_status].present?
      @nav_params[:payment_type] = params[:payment_type] if params[:payment_type].present?
      @nav_params[:dues_status] = params[:dues_status] if params[:dues_status].present?
      @nav_params[:active] = params[:active] if params[:active].present?
      @nav_params[:sort] = params[:sort] if params[:sort].present?
      @nav_params[:direction] = params[:direction] if params[:direction].present?
    end

    # Member help - show to users viewing their own profile
    # Use true_user to ensure impersonation doesn't trigger the help for the admin
    @member_help_content = TextFragment.content_for('member_help')
    @show_member_help_auto = false
    
    if @member_help_content.present? && true_user && true_user.id == @user.id && !impersonating?
      # Show automatically on first view (use true_user to not affect impersonated users)
      @show_member_help_auto = !true_user.seen_member_help
    end
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)

    if @user.save
      redirect_to user_path(@user), notice: 'Member created successfully.'
    else
      flash.now[:alert] = 'Unable to create member.'
      render :new, status: :unprocessable_entity
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

  def sync_to_authentik
    if @user.authentik_id.blank?
      redirect_to user_path(@user), alert: 'User does not have an Authentik ID.'
      return
    end

    sync = Authentik::UserSync.new(@user)
    result = sync.sync_to_authentik!

    case result[:status]
    when 'synced'
      redirect_to user_path(@user), notice: 'User synced to Authentik successfully.'
    when 'skipped'
      redirect_to user_path(@user), notice: "Sync skipped: #{result[:reason]}"
    when 'error'
      redirect_to user_path(@user), alert: "Sync failed: #{result[:error]}"
    end
  end

  def sync_from_authentik
    if @user.authentik_id.blank?
      redirect_to user_path(@user), alert: 'User does not have an Authentik ID.'
      return
    end

    # Prevent sync loop
    Current.skip_authentik_sync = true
    sync = Authentik::UserSync.new(@user)
    result = sync.sync_from_authentik!
    Current.skip_authentik_sync = false

    case result[:status]
    when 'updated'
      redirect_to user_path(@user), notice: "User updated from Authentik: #{result[:changes].join(', ')}"
    when 'no_changes'
      redirect_to user_path(@user), notice: 'No changes from Authentik.'
    when 'error'
      redirect_to user_path(@user), alert: "Sync failed: #{result[:error]}"
    end
  end

  # Mark member help as seen (only for the user themselves)
  def mark_help_seen
    # Use true_user to ensure impersonation doesn't mark the impersonated user's help as seen
    if true_user && true_user.id == @user.id
      true_user.update_column(:seen_member_help, true)
      head :ok
    else
      head :forbidden
    end
  end

  private

  def set_user_for_show
    @user = User.includes(:sheet_entry, :slack_user, :rfids, :user_links, trainings_as_trainee: :training_topic,
                           training_topics: []).find_by_param(params[:id])
  end

  def set_user
    @user = User.find_by_param(params[:id])
  end

  def authorize_self_or_admin
    # True admins can edit anyone (even when impersonating)
    return if true_user_admin?
    return if @user == current_user

    redirect_to user_path(current_user), alert: 'You may only edit your own profile.'
  end

  def authorize_profile_view
    # True admins can see everything (even when impersonating)
    return if true_user_admin?

    # Users can see their own profile
    return if user_signed_in? && @user == current_user

    # Check profile visibility settings
    case @user.profile_visibility
    when 'public'
      # Anyone can view
      true
    when 'members'
      # Must be logged in
      unless user_signed_in?
        redirect_to login_path, alert: 'Please sign in to view this profile.'
      end
    when 'private'
      # Only admin or self (already checked above)
      if user_signed_in?
        redirect_to user_path(current_user), alert: 'This profile is private.'
      else
        redirect_to login_path, alert: 'Please sign in to view this profile.'
      end
    end
  end

  def determine_view_level
    # :admin - full access to everything
    # :self - user viewing their own profile (same as members view + edit)
    # :members - logged in member viewing another member's profile
    # :public - not logged in viewing a public profile

    return :admin if current_user_admin?
    return :self if user_signed_in? && @user == current_user
    return :members if user_signed_in?

    :public
  end

  def determine_effective_view_level
    # Check if user is requesting a specific view level via params
    requested_view = params[:view_as]&.to_sym

    return @natural_view_level unless requested_view.present?

    # Validate that the user can access the requested view level
    allowed_views = allowed_preview_views
    return @natural_view_level unless allowed_views.include?(requested_view)

    requested_view
  end

  def allowed_preview_views
    # Admins can preview all views
    return %i[public members self admin] if current_user_admin?

    # Profile owners can preview public, members, and self views
    return %i[public members self] if user_signed_in? && @user == current_user

    # Others cannot preview
    []
  end

  def setup_view_preview_options
    # Don't show preview selector when impersonating - show exact user view
    @can_preview_views = !impersonating? && allowed_preview_views.length > 1
    @available_views = allowed_preview_views.map do |level|
      label = case level
              when :public then 'Public (not logged in)'
              when :members then 'Other Members'
              when :self then 'Profile Owner'
              when :admin then 'Admin'
              end
      [label, level]
    end
  end

  def user_params
    permitted = %i[
      username full_name email pronouns profile_visibility bio greeting_name use_full_name_for_greeting
      use_username_for_greeting do_not_greet
    ]

    if current_user_admin?
      permitted += %i[membership_status payment_type notes active membership_plan_id]
      permitted << :is_admin
    end

    params.require(:user).permit(permitted)
  end
end
