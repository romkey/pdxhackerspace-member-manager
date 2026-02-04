require 'csv'

class SlackUsersController < AdminController
  SORTABLE_COLUMNS = %w[display_name email is_admin is_owner is_bot deleted].freeze

  def index
    # Calculate counts from ALL slack users (before filtering)
    all_slack_users = SlackUser.all
    @total_count = all_slack_users.count
    @linked_count = all_slack_users.where.not(user_id: nil).count
    @unlinked_count = all_slack_users.where(user_id: nil, is_bot: false, dont_link: false).count
    @dont_link_count = all_slack_users.where(dont_link: true).count
    @admin_count = all_slack_users.where(is_admin: true).count
    @owner_count = all_slack_users.where(is_owner: true).count
    @bot_count = all_slack_users.where(is_bot: true).count
    @human_count = all_slack_users.where(is_bot: false).count
    @active_count = all_slack_users.where(deleted: false).count
    @deactivated_count = all_slack_users.where(deleted: true).count

    # Build filtered query using shared method (with eager loading for display)
    @slack_users = build_filtered_query.includes(:user)

    # Store sort info for view
    @sort_column = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : 'display_name'
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'

    # Track if any filter is active
    @filter_active = params[:linked].present? || params[:is_admin].present? ||
                     params[:is_owner].present? || params[:is_bot].present? || params[:status].present?
    @filtered_count = @slack_users.count if @filter_active

    # Store filter/sort params for links using shared method
    @list_params = extract_filter_params
  end

  def show
    @slack_user = SlackUser.includes(:user).find(params[:id])

    # Get all users for the selection dropdown (if no match found)
    @all_users = User.ordered_by_display_name if @slack_user.user.nil?

    # Store filter/sort params FIRST for use in view links
    # This ensures params are captured before any processing
    @nav_params = extract_filter_params

    # Rebuild the same filtered/sorted query from the index page for navigation
    nav_query = build_filtered_query
    
    ordered_ids = nav_query.pluck(:id)
    current_index = ordered_ids.index(@slack_user.id)

    if current_index
      @previous_slack_user = current_index.positive? ? SlackUser.find(ordered_ids[current_index - 1]) : nil
      @next_slack_user = current_index < ordered_ids.length - 1 ? SlackUser.find(ordered_ids[current_index + 1]) : nil
    else
      # Current user not in filtered list - show no navigation
      @previous_slack_user = nil
      @next_slack_user = nil
    end
  end

  def link_user
    @slack_user = SlackUser.find(params[:id])
    user = User.find(params[:user_id])

    # Link the slack user to the user
    # The SlackUser after_save callback will call user.on_slack_user_linked
    # to handle email syncing and Slack profile data
    @slack_user.update!(user_id: user.id)

    redirect_to slack_user_path(@slack_user),
                notice: "Linked to user #{user.display_name} and updated their Slack information."
  end

  def toggle_dont_link
    @slack_user = SlackUser.find(params[:id])
    new_value = !@slack_user.dont_link
    @slack_user.update!(dont_link: new_value)
    
    notice = new_value ? "#{@slack_user.display_name} marked as Don't Link." : "#{@slack_user.display_name} unmarked as Don't Link."
    redirect_to slack_user_path(@slack_user), notice: notice
  end

  def sync
    Slack::UserSyncJob.perform_later
    redirect_to slack_users_path, notice: 'Slack user sync started.'
  end

  def sync_to_users
    linked_count = 0
    skipped_count = 0

    # Only process real users (not bots) that aren't already linked
    SlackUser.where(is_bot: false, user_id: nil).find_each do |slack_user|
      # Find matching users by email or full name (real_name)
      matches = []

      # Match by email (case-insensitive) - check both primary email and extra_emails
      if slack_user.email.present?
        normalized_email = slack_user.email.to_s.strip.downcase
        # Match by primary email
        matches += User.where('LOWER(email) = ?', normalized_email)
        # Match by extra_emails array (case-insensitive)
        matches += User.where('EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)',
                              normalized_email)
      end

      # Match by full name (real_name)
      if slack_user.real_name.present?
        matches += User.where('LOWER(full_name) = ?', slack_user.real_name.downcase)
      end

      # Remove duplicates
      matches = matches.uniq

      # Only link if exactly one match (do not create new users)
      if matches.one?
        user = matches.first

        # Link the slack user to the user
        # The SlackUser after_save callback will call user.on_slack_user_linked
        # to handle email syncing and Slack profile data
        slack_user.update!(user_id: user.id)

        linked_count += 1
      else
        # No match or multiple matches, skip
        skipped_count += 1
      end
    end

    parts = []
    parts << "#{linked_count} linked" if linked_count.positive?
    parts << "#{skipped_count} skipped" if skipped_count.positive?

    notice = if parts.any?
               "Sync complete. #{parts.join(', ')}."
             else
               'Sync complete. No changes.'
             end

    redirect_to slack_users_path, notice: notice
  end

  def import_members
    if params[:file].blank?
      redirect_to slack_users_path, alert: 'Please choose a CSV file to import.'
      return
    end

    counts = Slack::CsvMemberImporter.new.call(params[:file])

    parts = []
    parts << "#{counts[:imported]} imported"
    parts << "#{counts[:updated]} updated"
    parts << "#{counts[:skipped]} skipped" if counts[:skipped].positive?

    redirect_to slack_users_path, notice: "Import complete: #{parts.join(', ')}."
  rescue CSV::MalformedCSVError => e
    redirect_to slack_users_path, alert: "Invalid CSV: #{e.message}"
  end

  def import_analytics
    if params[:file].blank?
      redirect_to slack_users_path, alert: 'Please choose a CSV file to import.'
      return
    end

    counts = Slack::CsvAnalyticsImporter.new.call(params[:file])

    parts = []
    parts << "#{counts[:updated]} updated"
    parts << "#{counts[:skipped]} skipped" if counts[:skipped].positive?

    redirect_to slack_users_path, notice: "Analytics import complete: #{parts.join(', ')}."
  rescue CSV::MalformedCSVError => e
    redirect_to slack_users_path, alert: "Invalid CSV: #{e.message}"
  end

  private

  # Extract filter/sort params from request for use in navigation links
  def extract_filter_params
    filter_params = {}
    filter_params[:linked] = params[:linked] if params[:linked].present?
    filter_params[:is_admin] = params[:is_admin] if params[:is_admin].present?
    filter_params[:is_owner] = params[:is_owner] if params[:is_owner].present?
    filter_params[:is_bot] = params[:is_bot] if params[:is_bot].present?
    filter_params[:status] = params[:status] if params[:status].present?
    filter_params[:sort] = params[:sort] if params[:sort].present?
    filter_params[:direction] = params[:direction] if params[:direction].present?
    filter_params
  end

  # Build a filtered and sorted query based on current params
  def build_filtered_query
    query = SlackUser.all

    # Apply linked/unlinked/dont_link filter
    case params[:linked]
    when 'yes'
      query = query.where.not(user_id: nil)
    when 'no'
      # Unlinked = no user_id, not a bot, not marked as dont_link
      query = query.where(user_id: nil, is_bot: false, dont_link: false)
    when 'dont_link'
      query = query.where(dont_link: true)
    end

    # Apply role filters
    query = query.where(is_admin: true) if params[:is_admin] == 'yes'
    query = query.where(is_admin: false) if params[:is_admin] == 'no'
    query = query.where(is_owner: true) if params[:is_owner] == 'yes'
    query = query.where(is_owner: false) if params[:is_owner] == 'no'

    # Apply type filters
    query = query.where(is_bot: true) if params[:is_bot] == 'yes'
    query = query.where(is_bot: false) if params[:is_bot] == 'no'

    # Apply status filter
    query = query.where(deleted: false) if params[:status] == 'active'
    query = query.where(deleted: true) if params[:status] == 'deactivated'

    # Apply sorting
    sort_column = SORTABLE_COLUMNS.include?(params[:sort]) ? params[:sort] : 'display_name'
    sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'
    query.order("#{sort_column} #{sort_direction} NULLS LAST")
  end
end
