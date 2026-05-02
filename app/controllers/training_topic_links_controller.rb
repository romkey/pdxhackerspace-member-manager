# Manages resource links for training topics. Topic setup is admin-only;
# trainers use the Train a Member workflow without editing topic resources.
class TrainingTopicLinksController < AuthenticatedController
  before_action :require_admin!
  before_action :set_training_topic
  before_action :set_link, only: %i[update destroy]

  def create
    @link = @training_topic.links.build(link_params)

    if @link.save
      redirect_to edit_training_topic_path(@training_topic), notice: 'Link added successfully.'
    else
      redirect_to edit_training_topic_path(@training_topic),
                  alert: "Failed to add link: #{@link.errors.full_messages.join(', ')}"
    end
  end

  def update
    if @link.update(link_params)
      redirect_to edit_training_topic_path(@training_topic), notice: 'Link updated successfully.'
    else
      redirect_to edit_training_topic_path(@training_topic),
                  alert: "Failed to update link: #{@link.errors.full_messages.join(', ')}"
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

  def set_link
    @link = @training_topic.links.find(params[:id])
  end

  def link_params
    params.expect(training_topic_link: %i[title url])
  end
end
