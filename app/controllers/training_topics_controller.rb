class TrainingTopicsController < AdminController
  def index
    @training_topics = TrainingTopic.order(:name)
  end

  def create
    @training_topic = TrainingTopic.new(training_topic_params)
    @training_topics = TrainingTopic.order(:name)

    if @training_topic.save
      redirect_to training_topics_path, notice: 'Training topic created successfully.'
    else
      render :index, status: :unprocessable_content
    end
  end

  def edit
    @training_topic = TrainingTopic.find(params[:id])
    # Get distinct users trained in this topic (use subquery to avoid PostgreSQL DISTINCT/ORDER BY conflict)
    trained_user_ids = Training.where(training_topic_id: @training_topic.id).select(:trainee_id).distinct
    @trained_users = User.where(id: trained_user_ids).order(:full_name, :email)
    # Get users who can train this topic
    @trainer_users = @training_topic.trainers.order(:full_name, :email)
    # Get all users for the training search
    @users_for_search = User.ordered_by_display_name
  end

  def update
    @training_topic = TrainingTopic.find(params[:id])

    if @training_topic.update(training_topic_params)
      redirect_to edit_training_topic_path(@training_topic), notice: 'Training topic updated successfully.'
    else
      # Reload the associations for the view (use subquery to avoid PostgreSQL DISTINCT/ORDER BY conflict)
      trained_user_ids = Training.where(training_topic_id: @training_topic.id).select(:trainee_id).distinct
      @trained_users = User.where(id: trained_user_ids).order(:full_name, :email)
      @trainer_users = @training_topic.trainers.order(:full_name, :email)
      @users_for_search = User.ordered_by_display_name
      render :edit, status: :unprocessable_entity
    end
  end

  def revoke_training
    @training_topic = TrainingTopic.find(params[:id])
    user = User.find(params[:user_id])

    # Delete all trainings for this user and topic
    deleted_count = @training_topic.trainings.where(trainee: user).delete_all

    if deleted_count > 0
      redirect_to edit_training_topic_path(@training_topic), notice: "Training revoked for #{user.display_name}."
    else
      redirect_to edit_training_topic_path(@training_topic), alert: "No training found to revoke for #{user.display_name}."
    end
  end

  def revoke_trainer_capability
    @training_topic = TrainingTopic.find(params[:id])
    user = User.find(params[:user_id])

    # Delete the trainer capability
    trainer_capability = TrainerCapability.find_by(user: user, training_topic: @training_topic)

    if trainer_capability&.destroy
      redirect_to edit_training_topic_path(@training_topic), notice: "Trainer capability revoked for #{user.display_name}."
    else
      redirect_to edit_training_topic_path(@training_topic), alert: "No trainer capability found to revoke for #{user.display_name}."
    end
  end

  def destroy
    @training_topic = TrainingTopic.find(params[:id])

    if @training_topic.trainings.any? || @training_topic.trainer_capabilities.any?
      redirect_to training_topics_path,
                  alert: 'Cannot delete training topic that has trainings or trainer capabilities.'
    else
      @training_topic.destroy
      redirect_to training_topics_path, notice: 'Training topic deleted successfully.'
    end
  end

  private

  def training_topic_params
    params.require(:training_topic).permit(:name)
  end
end
