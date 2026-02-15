class AccessLogsController < AdminController
  PER_PAGE = 200

  def index
    base_logs = AccessLog.includes(:user).recent

    # Calculate counts before filtering
    @total_count = base_logs.count
    @linked_count = base_logs.where.not(user_id: nil).count
    @unlinked_count = base_logs.where(user_id: nil).where.not(name: [nil, '']).count
    @no_name_count = base_logs.where(user_id: nil, name: [nil, '']).count

    @access_logs = base_logs

    # Apply linked/unlinked filter
    case params[:linked]
    when 'yes'
      @access_logs = @access_logs.where.not(user_id: nil)
    when 'no'
      @access_logs = @access_logs.where(user_id: nil).where.not(name: [nil, ''])
    when 'no_name'
      @access_logs = @access_logs.where(user_id: nil, name: [nil, ''])
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

  def import
    AccessLogsImportJob.perform_later
    redirect_to access_logs_path, notice: 'Access log import started.'
  end
end
