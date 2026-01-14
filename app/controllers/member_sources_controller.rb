class MemberSourcesController < AdminController
  before_action :set_member_source, only: [:show, :edit, :update, :toggle, :refresh_stats]

  def index
    @member_sources = MemberSource.ordered
  end

  def show; end

  def edit; end

  def update
    if @member_source.update(member_source_params)
      redirect_to member_sources_path, notice: "#{@member_source.name} settings updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle
    @member_source.update!(enabled: !@member_source.enabled)
    status = @member_source.enabled? ? 'enabled' : 'disabled'
    redirect_to member_sources_path, notice: "#{@member_source.name} has been #{status}."
  end

  def refresh_stats
    @member_source.check_api_configuration!
    @member_source.refresh_statistics!
    redirect_to member_sources_path, notice: "#{@member_source.name} statistics refreshed."
  end

  def refresh_all
    MemberSource.find_each do |source|
      source.check_api_configuration!
      source.refresh_statistics!
    end
    redirect_to member_sources_path, notice: "All member source statistics refreshed."
  end

  def seed
    MemberSource.seed_defaults!
    redirect_to member_sources_path, notice: "Member sources seeded."
  end

  private

  def set_member_source
    @member_source = MemberSource.find(params[:id])
  end

  def member_source_params
    params.require(:member_source).permit(:name, :enabled, :display_order, :notes)
  end
end
