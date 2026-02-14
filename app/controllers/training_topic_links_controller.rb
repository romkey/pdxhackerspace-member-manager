class TrainingTopicLinksController < AuthenticatedController
  before_action :set_training_topic
  before_action :require_trainer_or_admin_for_topic!
  before_action :set_link, only: [:update, :destroy]

  def create
    @link = @training_topic.links.build(link_params)

    if @link.save
      redirect_to edit_training_topic_path(@training_topic), notice: 'Link added successfully.'
    else
      redirect_to edit_training_topic_path(@training_topic), alert: "Failed to add link: #{@link.errors.full_messages.join(', ')}"
    end
  end

  def update
    if @link.update(link_params)
      redirect_to edit_training_topic_path(@training_topic), notice: 'Link updated successfully.'
    else
      redirect_to edit_training_topic_path(@training_topic), alert: "Failed to update link: #{@link.errors.full_messages.join(', ')}"
    end
  end

  def destroy
    @link.destroy
    redirect_to edit_training_topic_path(@training_topic), notice: 'Link removed successfully.'
  end

  private

  def set_training_topic
    @training_topic = TrainingTopic.find(params[:training_topic_id])
  end

  def require_trainer_or_admin_for_topic!
    return if current_user_admin?
    return if current_user.training_topics.include?(@training_topic)

    redirect_to root_path, alert: "You don't have permission to manage links for this training topic."
  end

  def set_link
    @link = @training_topic.links.find(params[:id])
  end

  def link_params
    params.require(:training_topic_link).permit(:title, :url)
  end
end
