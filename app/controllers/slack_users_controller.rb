class SlackUsersController < AuthenticatedController
  def index
    @show_bots = ActiveModel::Type::Boolean.new.cast(params[:show_bots])
    scope = @show_bots ? SlackUser.all : SlackUser.where(is_bot: false)
    @slack_users = scope.order(:display_name, :real_name, :username)
    @total_slack_users = @slack_users.count
    user_emails = User.where.not(email: nil).pluck(:email)
    user_names = User.where.not(full_name: nil).pluck(:full_name)
    @shared_email_count = SlackUser.where(email: user_emails).count
    @shared_name_count = SlackUser.where(real_name: user_names).or(SlackUser.where(display_name: user_names)).count
  end

  def show
    @slack_user = SlackUser.find(params[:id])
  end

  def sync
    Slack::UserSyncJob.perform_later
    redirect_to slack_users_path, notice: "Slack user sync started."
  end
end

