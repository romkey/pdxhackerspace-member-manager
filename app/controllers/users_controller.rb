class UsersController < AuthenticatedController
  skip_before_action :require_authenticated_user!, only: [:show]
  before_action :set_user_for_show, only: [:show]
  before_action :set_user,
                only: %i[edit update activate deactivate
                         enable_emergency_active_override clear_emergency_active_override
                         ban mark_deceased mark_sponsored
                         unmark_sponsored destroy
                         sync_to_authentik sync_from_authentik
                         mark_help_seen]
  before_action :require_admin!, except: %i[show edit update mark_help_seen]
  before_action :authorize_profile_view, only: [:show]
  before_action :authorize_self_or_admin, only: %i[edit update]

  SORTABLE_COLUMNS = %w[username full_name email membership_status payment_type last_synced_at].freeze

  def index
    # Start with all users for the "all" count
    all_users = User.all
    @all_user_count = all_users.count

    # Legacy count (from all users)
    @legacy_count = all_users.legacy.count

    # Include legacy members when checkbox is checked
    @include_legacy = params[:include_legacy] == '1'
    default_users = @include_legacy ? all_users : all_users.non_legacy

    # Build the base filter params hash (used for stacking links)
    @filter_params = {}
    @filter_params[:include_legacy] = '1' if @include_legacy
    @filter_params[:membership_status] = params[:membership_status] if params[:membership_status].present?
    @filter_params[:payment_type] = params[:payment_type] if params[:payment_type].present?
    @filter_params[:dues_status] = params[:dues_status] if params[:dues_status].present?
    @filter_params[:active] = params[:active] if params[:active].present?
    @filter_params[:membership_plan_id] = params[:membership_plan_id] if params[:membership_plan_id].present?
    @filter_params[:missing] = params[:missing] if params[:missing].present?
    @filter_params[:account_type] = params[:account_type] if params[:account_type].present?
    if params[:emergency_active_override].present?
      @filter_params[:emergency_active_override] = params[:emergency_active_override]
    end
    @filter_params[:sort] = params[:sort] if params[:sort].present?
    @filter_params[:direction] = params[:direction] if params[:direction].present?

    # Build filtered query by applying all active filters
    @users = default_users

    if params[:q].present?
      search_term = "%#{params[:q].downcase}%"
      @users = @users.where(
        "LOWER(COALESCE(full_name, '')) LIKE :p " \
        "OR LOWER(COALESCE(email, '')) LIKE :p " \
        'OR LOWER(authentik_id) LIKE :p ' \
        "OR LOWER(COALESCE(username, '')) LIKE :p",
        p: search_term
      )
    end

    if params[:membership_status].present?
      @users = @users.non_service_accounts.where(membership_status: params[:membership_status])
    end
    @users = @users.non_service_accounts.where(payment_type: params[:payment_type]) if params[:payment_type].present?
    @users = @users.non_service_accounts.where(dues_status: params[:dues_status]) if params[:dues_status].present?
    if params[:membership_plan_id].present?
      @users = if params[:membership_plan_id] == 'none'
                 @users.non_service_accounts.where(membership_plan_id: nil)
               else
                 @users.non_service_accounts.where(membership_plan_id: params[:membership_plan_id])
               end
    end
    @users = @users.where(active: params[:active] == 'true') if params[:active].present?

    if params[:account_type] == 'service'
      @users = @users.service_accounts
    elsif params[:account_type] == 'member'
      @users = @users.non_service_accounts
    end

    if params[:emergency_active_override] == '1'
      @users = @users.non_service_accounts.where(emergency_active_override: true)
    end

    if params[:missing] == 'rfid'
      @users = @users.non_service_accounts.where.missing(:rfids)
    elsif params[:missing] == 'email'
      @users = @users.non_service_accounts.where("email IS NULL OR email = ''")
    end

    # Total count always from the full (non-legacy-adjusted) set for the "X of Y" message
    @user_count = default_users.count

    # Active/inactive counts from the filtered set
    @active_count = @users.where(active: true).count
    @inactive_count = @users.where(active: false).count

    # Badge counts from the filtered set so they reflect stacked filters
    filtered_members = @users.non_service_accounts

    @membership_status_unknown = filtered_members.where(membership_status: 'unknown', is_sponsored: false).count
    @membership_status_sponsored = filtered_members.where(membership_status: 'sponsored').count
    @membership_status_paying = filtered_members.where(membership_status: 'paying').count
    @membership_status_banned = filtered_members.where(membership_status: 'banned').count
    @membership_status_deceased = filtered_members.where(membership_status: 'deceased').count
    @membership_status_applicant = filtered_members.where(membership_status: 'applicant').count

    @payment_type_unknown = filtered_members.where(payment_type: 'unknown').count
    @payment_type_sponsored = filtered_members.where(payment_type: 'sponsored').count
    @payment_type_paypal = filtered_members.where(payment_type: 'paypal').count
    @payment_type_recharge = filtered_members.where(payment_type: 'recharge').count
    @payment_type_cash = filtered_members.where(payment_type: 'cash').count

    @membership_plans = MembershipPlan.ordered.to_a
    @plan_counts = @membership_plans.map { |plan| [plan, filtered_members.where(membership_plan_id: plan.id).count] }
    @no_plan_count = filtered_members.where(membership_plan_id: nil)
                                     .where.not(membership_status: %w[guest sponsored])
                                     .where(is_sponsored: false)
                                     .count

    @dues_status_current = filtered_members.where(dues_status: 'current').count
    @dues_status_lapsed = filtered_members.where(dues_status: 'lapsed').count
    @dues_status_inactive = filtered_members.where(dues_status: 'inactive').count
    @dues_status_unknown = filtered_members.where(dues_status: 'unknown').count

    @no_rfid_count = filtered_members.where.missing(:rfids).count
    @no_email_count = filtered_members.where("email IS NULL OR email = ''").count

    @service_account_count = @users.service_accounts.count
    @member_account_count = @users.non_service_accounts.count
    @emergency_active_override_count = all_users.non_service_accounts.where(emergency_active_override: true).count

    # Apply sorting — use Arel nodes to avoid string interpolation (CodeQL SQL injection rule)
    @sort_column = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : 'full_name'
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
    col_node = User.arel_table[@sort_column]
    direction_node = @sort_direction == 'desc' ? col_node.desc : col_node.asc
    @users = @users.order(Arel::Nodes::NullsLast.new(direction_node))

    # Track if any filter is active (including legacy toggle)
    @filter_active = params[:membership_status].present? || params[:payment_type].present? ||
                     params[:dues_status].present? || params[:active].present? ||
                     params[:missing].present? || params[:account_type].present? ||
                     params[:membership_plan_id].present? ||
                     params[:emergency_active_override].present?
    @filtered_count = @users.count if @filter_active || @include_legacy

    # Store filter/sort params for passing to user profile links
    @list_params = @filter_params.dup

    @recent_members = User.non_service_accounts.non_legacy
                          .where(created_at: 1.week.ago..)
                          .ordered_by_display_name
  end

  def show
    # Determine view level based on viewer and profile settings
    @natural_view_level = determine_view_level
    @view_level = determine_effective_view_level

    # Set up view preview options for admins and profile owners
    setup_view_preview_options

    # Default tab
    requested_tab = params[:tab]&.to_sym
    @active_tab = if requested_tab.present?
                    requested_tab
                  elsif @view_level == :self
                    :dashboard
                  else
                    :profile
                  end

    # Parking notices for admin and self views
    if @view_level == :admin || @view_level == :self
      parking_query = @user.parking_notices.not_cleared.newest_first
      @parking_notices_count = parking_query.count
      @parking_notices_list = parking_query.limit(50)
    end

    # Messages for admin and self views
    if @view_level == :admin || @view_level == :self
      messages_query = @user.received_messages.includes(:sender).newest_first
      @messages_count = messages_query.count
      @unread_messages_count = @user.received_messages.unread.count
      @pagy_messages, @messages = pagy(messages_query, limit: 20, page_key: 'messages_page')

      if @view_level == :self && @active_tab == :messages
        @user.received_messages.unread.update_all(read_at: Time.current)
        @unread_messages_count = 0
      end
    end

    if @view_level == :self
      set_self_service_training_data
      set_member_dashboard_data
    end

    # Load payment history for admin and self views (paginated)
    if @view_level == :admin || @view_level == :self
      @payment_event_filter = params[:event_type].presence
      payments_query = PaymentHistory.for_user(@user, event_type: @payment_event_filter)
      @payments_count = payments_query.count
      @pagy_payments, @payments = pagy(payments_query, limit: 20, page_key: 'payments_page')
    end

    # Admin-only data (true admins, even when impersonating)
    if true_user_admin?
      # Journals (paginated) - only load for admin view
      if @view_level == :admin
        journals_query = @user.journals.includes(:actor_user).order(changed_at: :desc, created_at: :desc)
        @journals_count = journals_query.count
        @pagy_journals, @journals = pagy(journals_query, limit: 20, page_key: 'journal_page')

        # Access logs (paginated)
        access_query = @user.access_logs.order(logged_at: :desc)
        @access_count = access_query.count
        @most_recent_access = access_query.first
        @pagy_accesses, @recent_accesses = pagy(access_query, limit: 20, page_key: 'access_page')

        # Incidents (paginated)
        incidents_query = @user.incident_reports.includes(:reporter).ordered
        @incidents_count = incidents_query.count
        @pagy_incidents, @user_incidents = pagy(incidents_query, limit: 20, page_key: 'incidents_page')

        # Mail (queued mails for this recipient, with log entries)
        mail_query = @user.queued_mails.includes(:email_template, :reviewed_by, :mail_log_entries).newest_first
        @mail_count = mail_query.count
        @pagy_mails, @queued_mails = pagy(mail_query, limit: 20, page_key: 'mail_page')
      end

      # Find previous and next users for navigation (always for admin toolbar)
      # Rebuild the same filtered/sorted query from the index page
      nav_query = User.all

      # Apply filters if present
      nav_query = nav_query.where(membership_status: params[:membership_status]) if params[:membership_status].present?
      nav_query = nav_query.where(payment_type: params[:payment_type]) if params[:payment_type].present?
      nav_query = nav_query.where(dues_status: params[:dues_status]) if params[:dues_status].present?
      nav_query = nav_query.where(active: params[:active] == 'true') if params[:active].present?
      if params[:emergency_active_override] == '1'
        nav_query = nav_query.where(service_account: false, emergency_active_override: true)
      end

      # Apply sorting — use Arel nodes to avoid string interpolation (CodeQL SQL injection rule)
      sort_column = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : 'full_name'
      sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
      nav_col_node = User.arel_table[sort_column]
      nav_direction_node = sort_direction == 'desc' ? nav_col_node.desc : nav_col_node.asc
      nav_query = nav_query.order(Arel::Nodes::NullsLast.new(nav_direction_node))

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
      if params[:emergency_active_override].present?
        @nav_params[:emergency_active_override] = params[:emergency_active_override]
      end
      @nav_params[:sort] = params[:sort] if params[:sort].present?
      @nav_params[:direction] = params[:direction] if params[:direction].present?
    end

    # Member help - show to users viewing their own profile
    # Use true_user to ensure impersonation doesn't trigger the help for the admin
    @member_help_content = TextFragment.content_for('member_help')
    @show_member_help_auto = false

    return unless @member_help_content.present? && true_user && true_user.id == @user.id && !impersonating?

    # Show automatically on first view (use true_user to not affect impersonated users)
    @show_member_help_auto = !true_user.seen_member_help
  end

  def new
    @user = User.new
  end

  def edit
    return unless !true_user_admin? && @user == current_user

    redirect_to profile_setup_path
    nil
  end

  def create
    @user = User.new(resolved_user_params)

    if @user.save
      redirect_to user_path(@user), notice: 'Member created successfully.'
    else
      if @user.errors.of_kind?(:email, :taken)
        existing_user = find_existing_user_by_email(@user.email)
        flash.now[:alert] = if existing_user
                              helpers.safe_join(
                                [
                                  'Unable to create member: email is already in use by ',
                                  helpers.link_to(existing_user.display_name, user_path(existing_user)),
                                  '.'
                                ]
                              )
                            else
                              'Unable to create member: email is already in use.'
                            end
      else
        flash.now[:alert] = 'Unable to create member.'
      end
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @user.update(resolved_user_params)
      redirect_to user_path(@user), notice: 'Member updated successfully.'
    else
      flash.now[:alert] = 'Unable to update user.'
      render :edit, status: :unprocessable_content
    end
  end

  def sync
    unless MemberSource.enabled?('authentik')
      redirect_to users_path, alert: 'Authentik source is disabled.'
      return
    end

    Authentik::GroupSyncJob.perform_later
    redirect_to users_path, notice: 'Authentik group sync has been scheduled.'
  end

  def sync_all_to_authentik
    unless MemberSource.enabled?('member_manager')
      redirect_to users_path, alert: 'Member Manager source is disabled.'
      return
    end

    Authentik::FullSyncToAuthentikJob.perform_later
    redirect_to users_path,
                notice: 'Full sync to Authentik has been scheduled. ' \
                        'All members, application groups, and the active members group will be synced.'
  end

  def activate
    unless @user.service_account?
      redirect_to user_path(@user),
                  alert: 'Active status for non-service accounts is determined by membership and dues status.'
      return
    end
    @user.update!(active: true)
    redirect_to user_path(@user), notice: 'Account activated.'
  end

  def deactivate
    unless @user.service_account?
      redirect_to user_path(@user),
                  alert: 'Active status for non-service accounts is determined by membership and dues status.'
      return
    end
    @user.update!(active: false)
    redirect_to user_path(@user), notice: 'Account deactivated.'
  end

  def enable_emergency_active_override
    if @user.service_account?
      redirect_to user_path(@user), alert: 'Service accounts use Activate / Deactivate instead.'
      return
    end
    if @user.membership_status.in?(%w[banned deceased])
      redirect_to user_path(@user), alert: 'Active override is not available for banned or deceased members.'
      return
    end
    if @user.emergency_active_override?
      redirect_to user_path(@user), notice: 'Active override is already enabled.'
      return
    end
    if @user.active?
      redirect_to user_path(@user), alert: 'Member is already active.'
      return
    end

    @user.update!(emergency_active_override: true)
    redirect_to user_path(@user),
                notice: 'Active override enabled. They stay active until you clear the override.'
  end

  def clear_emergency_active_override
    unless @user.emergency_active_override?
      redirect_to user_path(@user), alert: 'Active override is not enabled.'
      return
    end

    @user.update!(emergency_active_override: false)
    redirect_to user_path(@user),
                notice: 'Active override cleared; active status was recalculated from membership.'
  end

  def ban
    @user.update!(membership_status: 'banned')
    QueuedMail.enqueue(:membership_banned, @user, reason: 'Member banned') if @user.email.present?
    redirect_to user_path(@user), notice: 'Member banned.'
  end

  def mark_deceased
    @user.update!(membership_status: 'deceased')
    redirect_to user_path(@user), notice: 'Member marked as deceased.'
  end

  def mark_sponsored
    @user.update!(is_sponsored: true)
    QueuedMail.enqueue(:membership_sponsored, @user, reason: 'Membership sponsored') if @user.email.present?
    redirect_to user_path(@user), notice: 'Member marked as sponsored.'
  end

  def unmark_sponsored
    @user.update!(is_sponsored: false)
    redirect_to user_path(@user), notice: 'Member sponsorship removed.'
  end

  def destroy
    @user.destroy!
    redirect_to users_path, notice: 'Member deleted successfully.'
  end

  def sync_to_authentik
    unless MemberSource.enabled?('member_manager')
      redirect_to user_path(@user), alert: 'Member Manager source is disabled.'
      return
    end

    if @user.authentik_id.blank?
      redirect_to user_path(@user), alert: 'Member does not have an Authentik ID.'
      return
    end

    sync = Authentik::UserSync.new(@user)
    result = sync.sync_to_authentik!

    case result[:status]
    when 'synced'
      redirect_to user_path(@user), notice: 'Member synced to Authentik successfully.'
    when 'skipped'
      redirect_to user_path(@user), notice: "Sync skipped: #{result[:reason]}"
    when 'error'
      redirect_to user_path(@user), alert: "Sync failed: #{result[:error]}"
    end
  end

  def sync_from_authentik
    unless MemberSource.enabled?('authentik')
      redirect_to user_path(@user), alert: 'Authentik source is disabled.'
      return
    end

    if @user.authentik_id.blank?
      redirect_to user_path(@user), alert: 'Member does not have an Authentik ID.'
      return
    end

    # Prevent sync loop
    Current.skip_authentik_sync = true
    sync = Authentik::UserSync.new(@user)
    result = sync.sync_from_authentik!
    Current.skip_authentik_sync = false

    case result[:status]
    when 'updated'
      redirect_to user_path(@user), notice: "Member updated from Authentik: #{result[:changes].join(', ')}"
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
    @user = User.includes(
      :sheet_entry, :slack_user, :rfids, :user_links, :membership_applications,
      trainings_as_trainee: :training_topic, training_topics: []
    ).find_by_param(params[:id])
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
      redirect_to login_path, alert: 'Please sign in to view this profile.' unless user_signed_in?
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

    return @natural_view_level if requested_view.blank?

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
    view_labels = {
      public: 'Public (not logged in)',
      members: 'Other Members',
      self: 'Profile Owner',
      admin: 'Admin'
    }.freeze
    @available_views = allowed_preview_views.map { |level| [view_labels[level], level] }
  end

  def set_self_service_training_data
    @member_requestable_topics = TrainingTopic.available_for_member_requests

    trainer_topic_ids = current_user.training_topics.select(:id)
    ordering = 'training_topics.name ASC, training_requests.created_at DESC'
    @trainer_training_requests_by_topic = TrainingRequest.pending
                                                         .where(training_topic_id: trainer_topic_ids)
                                                         .joins(:training_topic)
                                                         .includes(:training_topic, :user)
                                                         .order(ordering)
                                                         .group_by(&:training_topic)
  end

  def set_member_dashboard_data
    @member_dashboard_attention_items = []
    @member_dashboard_ok_items = []

    append_member_dashboard_payment_item
    append_member_dashboard_training_item
    append_member_dashboard_slack_item
    append_member_dashboard_parking_item
  end

  def append_member_dashboard_payment_item
    unless member_manual_payment?
      add_member_dashboard_item(
        ok: true,
        id: :cash_payment_due,
        tier: :none,
        title: 'Cash payment due',
        detail: 'You are not on a manual/cash payment plan.'
      )
      return
    end

    due_on = @user.next_payment_date
    if due_on.blank?
      add_member_dashboard_item(
        ok: false,
        id: :cash_payment_due,
        tier: :housekeeping,
        title: 'Cash payment due',
        detail: 'No next payment due date is recorded yet. Please contact an admin.',
        action_label: 'View payment history',
        action_path: user_path(@user, tab: :payments, view_as: params[:view_as])
      )
      return
    end

    days_until = (due_on - Date.current).to_i
    if days_until.negative?
      add_member_dashboard_item(
        ok: false,
        id: :cash_payment_due,
        tier: :urgent,
        title: 'Cash payment due',
        detail: "Your next cash payment was due #{due_on.strftime('%B %-d, %Y')} (#{days_until.abs} days overdue).",
        action_label: 'View payment history',
        action_path: user_path(@user, tab: :payments, view_as: params[:view_as])
      )
      return
    end

    due_soon_days = MembershipSetting.manual_payment_due_soon_days
    if days_until <= due_soon_days
      add_member_dashboard_item(
        ok: false,
        id: :cash_payment_due,
        tier: :important,
        title: 'Cash payment due soon',
        detail: "Your next cash payment is due in #{days_until} days (#{due_on.strftime('%B %-d, %Y')}).",
        action_label: 'View payment history',
        action_path: user_path(@user, tab: :payments, view_as: params[:view_as])
      )
      return
    end

    add_member_dashboard_item(
      ok: true,
      id: :cash_payment_due,
      tier: :none,
      title: 'Cash payment due',
      detail: "Your next cash payment is due in #{days_until} days (#{due_on.strftime('%B %-d, %Y')})."
    )
  end

  def append_member_dashboard_training_item
    pending_count = @user.training_requests.pending.count
    if pending_count.positive?
      add_member_dashboard_item(
        ok: false,
        id: :training_requests,
        tier: :important,
        title: 'Open training requests',
        detail: "You have #{pending_count} open training request#{'s' unless pending_count == 1}.",
        action_label: 'Open Profile tab',
        action_path: user_path(@user, tab: :profile, view_as: params[:view_as])
      )
      return
    end

    add_member_dashboard_item(
      ok: true,
      id: :training_requests,
      tier: :none,
      title: 'Open training requests',
      detail: 'You have no open training requests.'
    )
  end

  def append_member_dashboard_slack_item
    if @user.slack_user.present?
      add_member_dashboard_item(
        ok: true,
        id: :slack_signup,
        tier: :none,
        title: 'Slack account',
        detail: 'Your account is linked to Slack.'
      )
      return
    end

    if SlackOidcConfig.configured?
      add_member_dashboard_item(
        ok: false,
        id: :slack_signup,
        tier: :housekeeping,
        title: 'Slack account',
        detail: 'Link your CTRLH Slack workspace member to your profile so we can recognize you on Slack.',
        action_label: 'Associate Slack account',
        action_path: slack_link_start_path
      )
    else
      add_member_dashboard_item(
        ok: false,
        id: :slack_signup,
        tier: :housekeeping,
        title: 'Join Slack',
        detail: 'You do not have a linked Slack user yet. Please ask an admin for an invite.',
        action_label: 'View Profile',
        action_path: user_path(@user, tab: :profile, view_as: params[:view_as])
      )
    end
  end

  def append_member_dashboard_parking_item
    notices = @user.parking_notices.not_cleared
    expired_count = notices.expired_notices.count
    active_count = notices.active_notices.count
    open_count = expired_count + active_count

    if expired_count.positive?
      detail = "#{expired_count} expired and #{active_count} active open parking notice#{'s' unless open_count == 1}."
      add_member_dashboard_item(
        ok: false,
        id: :parking_notices,
        tier: :urgent,
        title: 'Open parking permits/tickets',
        detail: detail,
        action_label: 'Open Parking tab',
        action_path: user_path(@user, tab: :parking, view_as: params[:view_as])
      )
      return
    end

    if active_count.positive?
      add_member_dashboard_item(
        ok: false,
        id: :parking_notices,
        tier: :important,
        title: 'Open parking permits/tickets',
        detail: "#{active_count} active open parking notice#{'s' unless active_count == 1}.",
        action_label: 'Open Parking tab',
        action_path: user_path(@user, tab: :parking, view_as: params[:view_as])
      )
      return
    end

    add_member_dashboard_item(
      ok: true,
      id: :parking_notices,
      tier: :none,
      title: 'Open parking permits/tickets',
      detail: 'You have no open parking permits or tickets.'
    )
  end

  def member_manual_payment?
    return true if @user.payment_type == 'cash'

    @user.all_membership_plans.any?(&:manual?)
  end

  def add_member_dashboard_item(item)
    if item[:ok]
      @member_dashboard_ok_items << item
    else
      @member_dashboard_attention_items << item
    end
  end

  def user_params
    permitted = %i[
      username full_name email pronouns profile_visibility bio greeting_name greeting_option
      use_full_name_for_greeting use_username_for_greeting do_not_greet
    ]

    if current_user_admin?
      permitted += %i[
        membership_status payment_type notes membership_plan_id aliases_text service_account legacy
        dues_due_at sponsored_guest_duration_months
      ]
      permitted << :is_admin
      # Only allow manual active toggle for service accounts
      permitted << :active if @user&.service_account?
    end

    params.require(:user).permit(permitted)
  end

  def resolved_user_params
    attrs = user_params.to_h.symbolize_keys
    apply_greeting_option!(attrs)
    attrs
  end

  def apply_greeting_option!(attrs)
    option = attrs.delete(:greeting_option)
    return if option.blank?

    case option
    when 'full_name'
      attrs[:use_full_name_for_greeting] = true
      attrs[:use_username_for_greeting]  = false
      attrs[:do_not_greet]               = false
      attrs.delete(:greeting_name)
    when 'username'
      attrs[:use_full_name_for_greeting] = false
      attrs[:use_username_for_greeting]  = true
      attrs[:do_not_greet]               = false
      attrs.delete(:greeting_name)
    when 'custom'
      attrs[:use_full_name_for_greeting] = false
      attrs[:use_username_for_greeting]  = false
      attrs[:do_not_greet]               = false
    when 'do_not_greet'
      attrs[:use_full_name_for_greeting] = false
      attrs[:use_username_for_greeting]  = false
      attrs[:do_not_greet]               = true
      attrs[:greeting_name]              = ''
    end
  end

  def find_existing_user_by_email(email)
    normalized_email = email.to_s.strip.downcase
    return nil if normalized_email.blank?

    User.where('LOWER(email) = ?', normalized_email).first
  end
end
