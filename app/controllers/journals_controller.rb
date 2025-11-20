class JournalsController < AuthenticatedController
  def index
    @journals = Journal.includes(:user, :actor_user).order(changed_at: :desc, created_at: :desc)
  end
end
