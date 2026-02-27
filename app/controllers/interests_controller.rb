class InterestsController < AdminController
  before_action :set_interest, only: [:edit, :update, :destroy, :members, :merge_form, :merge]

  def index
    @interests = Interest.alphabetical.includes(:user_interests)
    @new_interest = Interest.new
  end

  def new
    @interest = Interest.new
  end

  def create
    @interest = Interest.new(interest_params)
    if @interest.save
      redirect_to interests_path, notice: "'#{@interest.name}' added."
    else
      @interests = Interest.alphabetical.includes(:user_interests)
      @new_interest = @interest
      render :index, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @interest.update(interest_params)
      redirect_to interests_path, notice: "Interest updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @interest.name
    @interest.destroy!
    redirect_to interests_path, notice: "'#{name}' removed."
  end

  def members
    @members = @interest.users.includes(:user_interests).order(:full_name)
  end

  def merge_form
    @target_interests = Interest.alphabetical.where.not(id: @interest.id)
  end

  def merge
    target = Interest.find(params[:target_interest_id])

    # Re-point all user_interests from @interest → target, skip duplicates
    @interest.user_interests.each do |ui|
      unless UserInterest.exists?(user_id: ui.user_id, interest_id: target.id)
        ui.update_columns(interest_id: target.id)
      end
    end

    name = @interest.name
    @interest.reload.destroy!
    redirect_to interests_path, notice: "'#{name}' merged into '#{target.name}'."
  rescue ActiveRecord::RecordNotFound
    redirect_to interests_path, alert: "Target interest not found."
  end

  private

  def set_interest
    @interest = Interest.find(params[:id])
  end

  def interest_params
    params.require(:interest).permit(:name)
  end
end
