class JournalsController < AdminController
  def index
    @journals = Journal.includes(:user, :actor_user).order(changed_at: :desc, created_at: :desc)
    @journals = @journals.highlighted if params[:filter] == 'highlights'
  end
end
