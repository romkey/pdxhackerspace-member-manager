class AccessLogsController < AuthenticatedController
  def index
    @access_logs = AccessLog.includes(:user).recent.limit(1000)
  end

  def generate_users_json
    users_data = {}
    
    # Find all active users with RFID records
    User.where(membership_status: "active").includes(:rfids, trainings_as_trainee: :training_topic).find_each do |user|
      next unless user.rfids.any?
      
      # Build permissions list: "active member" + training topics
      permissions = ["active member"]
      trained_topics = user.trainings_as_trainee.map(&:training_topic).uniq
      permissions += trained_topics.map(&:name)
      
      # Create one entry per RFID
      user.rfids.each do |rfid_record|
        users_data[rfid_record.rfid.to_s] = {
          "name" => user.full_name.presence || user.display_name,
          "permissions" => permissions
        }
      end
    end
    
    send_data(
      JSON.pretty_generate(users_data),
      filename: "users.json",
      type: "application/json",
      disposition: "attachment"
    )
  end
end

