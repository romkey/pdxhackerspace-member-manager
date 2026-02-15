class AccessLogsController < AdminController
  PER_PAGE = 200

  def index
    base_logs = AccessLog.includes(:user).recent

    # Calculate counts before filtering
    @total_count = base_logs.count
    @linked_count = base_logs.where.not(user_id: nil).count
    @unlinked_count = base_logs.where(user_id: nil).where.not(name: [nil, '']).count
    @no_name_count = base_logs.where(user_id: nil, name: [nil, '']).count
    @service_account_count = base_logs.joins(:user).where(users: { service_account: true }).count

    @access_logs = base_logs

    # Apply linked/unlinked filter
    case params[:linked]
    when 'yes'
      @access_logs = @access_logs.where.not(user_id: nil)
    when 'no'
      @access_logs = @access_logs.where(user_id: nil).where.not(name: [nil, ''])
    when 'no_name'
      @access_logs = @access_logs.where(user_id: nil, name: [nil, ''])
    when 'service'
      @access_logs = @access_logs.joins(:user).where(users: { service_account: true })
    end

    @filter_active = params[:linked].present?

    # Apply search filter if provided
    if params[:q].present?
      search_term = "%#{params[:q]}%"
      @access_logs = @access_logs.where(
        'name ILIKE ? OR location ILIKE ? OR raw_text ILIKE ?',
        search_term, search_term, search_term
      )
    end

    # Pagination
    @page = (params[:page] || 1).to_i
    @page = 1 if @page < 1
    @display_count = @access_logs.count
    @total_pages = (@display_count.to_f / PER_PAGE).ceil
    @access_logs = @access_logs.offset((@page - 1) * PER_PAGE).limit(PER_PAGE)

    # Load users for the link modal (only if there are unlinked entries)
    @all_users = User.ordered_by_display_name if @unlinked_count.positive?
  end

  def generate_users_json
    users_data = {}

    # Find all active users with RFID records
    User.where(active: true).includes(:rfids, trainings_as_trainee: :training_topic).find_each do |user|
      next unless user.rfids.any?

      # Build permissions list: "active member" + training topics
      permissions = ['active member']
      trained_topics = user.trainings_as_trainee.map(&:training_topic).uniq
      permissions += trained_topics.map(&:name)

      # Create one entry per RFID
      user.rfids.each do |rfid_record|
        users_data[rfid_record.rfid.to_s] = {
          'name' => user.full_name.presence || user.display_name,
          'permissions' => permissions
        }
      end
    end

    send_data(
      JSON.pretty_generate(users_data),
      filename: 'users.json',
      type: 'application/json',
      disposition: 'attachment'
    )
  end

  def link_user
    @log = AccessLog.find(params[:id])
    user = User.find(params[:user_id])

    @log.update!(user: user)

    # Add the access log name as an alias if it differs from the user's full_name
    user.add_alias!(@log.name) if @log.name.present?

    # Also link other unlinked access log entries with the same name
    linked_count = 0
    if @log.name.present?
      linked_count = AccessLog.where(user_id: nil, name: @log.name)
                              .update_all(user_id: user.id)
    end

    extra = linked_count.positive? ? " Also linked #{linked_count} other #{'entry'.pluralize(linked_count)} with the same name." : ''
    redirect_to access_logs_path(linked: params[:linked], q: params[:q], page: params[:page]),
                notice: "Linked '#{@log.name}' to #{user.display_name}.#{extra}"
  end

  def import
    AccessLogsImportJob.perform_later
    redirect_to access_logs_path, notice: 'Access log import started.'
  end
end
