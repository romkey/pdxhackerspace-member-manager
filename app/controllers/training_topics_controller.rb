class TrainingTopicsController < AuthenticatedController
  def index
    @training_topics = TrainingTopic.order(:name)
  end

  def create
    @training_topic = TrainingTopic.new(training_topic_params)
    @training_topics = TrainingTopic.order(:name)
    
    if @training_topic.save
      redirect_to training_topics_path, notice: "Training topic created successfully."
    else
      render :index, status: :unprocessable_content
    end
  end

  def destroy
    @training_topic = TrainingTopic.find(params[:id])
    
    if @training_topic.trainings.any? || @training_topic.trainer_capabilities.any?
      redirect_to training_topics_path, alert: "Cannot delete training topic that has trainings or trainer capabilities."
    else
      @training_topic.destroy
      redirect_to training_topics_path, notice: "Training topic deleted successfully."
    end
  end

  private

  def training_topic_params
    params.require(:training_topic).permit(:name)
  end
end
