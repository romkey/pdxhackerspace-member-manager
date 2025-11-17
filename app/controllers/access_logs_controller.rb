class AccessLogsController < AuthenticatedController
  def index
    @access_logs = AccessLog.includes(:user).recent.limit(1000)
  end

  def generate_users_json
    users_data = {}
    
    # Find all active users with RFID values
    User.where(membership_status: "active").find_each do |user|
      next unless user.rfid.present? && user.rfid.any?
      
      # Build permissions list: "active member" + training topics
      permissions = ["active member"]
      trained_topics = user.trainings_as_trainee.includes(:training_topic).map(&:training_topic).uniq
      permissions += trained_topics.map(&:name)
      
      # Create one entry per RFID
      user.rfid.each do |rfid|
        users_data[rfid.to_s] = {
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

