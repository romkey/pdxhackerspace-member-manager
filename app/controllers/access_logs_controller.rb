class AccessLogsController < AuthenticatedController
  def index
    @access_logs = AccessLog.includes(:user).recent.limit(1000)
  end
end

