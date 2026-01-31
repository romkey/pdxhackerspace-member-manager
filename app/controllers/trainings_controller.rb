class TrainingsController < AuthenticatedController
  before_action :require_trainer_or_admin
  before_action :set_trainee, only: [:add_training, :remove_training]
  before_action :set_training_topic, only: [:add_training, :remove_training]

  def index
    @users_for_search = User.active.ordered_by_display_name
    @trainable_topics = trainable_topics_for_current_user
  end

  def add_training
    unless can_train_topic?(@training_topic)
      redirect_to train_member_path, alert: "You don't have permission to train #{@training_topic.name}."
      return
    end

    # Check if training already exists
    existing = Training.find_by(trainee: @trainee, training_topic: @training_topic)
    if existing
      redirect_to train_member_path(user_id: @trainee.id), notice: "#{@trainee.display_name} is already trained in #{@training_topic.name}."
      return
    end

    training = Training.new(
      trainee: @trainee,
      trainer: current_user,
      training_topic: @training_topic,
      trained_at: Time.current
    )

    if training.save
      # Create journal entry for the trainee
      Journal.create!(
        user: @trainee,
        actor_user: current_user,
        action: 'training_added',
        changes_json: {
          'training' => {
            'topic' => @training_topic.name,
            'trainer' => current_user.display_name,
            'trained_at' => training.trained_at.iso8601
          }
        },
        changed_at: Time.current
      )
      redirect_to train_member_path(user_id: @trainee.id), notice: "#{@trainee.display_name} has been marked as trained in #{@training_topic.name}."
    else
      redirect_to train_member_path(user_id: @trainee.id), alert: "Failed to add training: #{training.errors.full_messages.join(', ')}"
    end
  end

  def remove_training
    unless can_train_topic?(@training_topic)
      redirect_to train_member_path, alert: "You don't have permission to manage #{@training_topic.name} training."
      return
    end

    trainings = Training.where(trainee: @trainee, training_topic: @training_topic)
    count = trainings.count

    if count > 0
      trainings.destroy_all
      # Create journal entry for the trainee
      Journal.create!(
        user: @trainee,
        actor_user: current_user,
        action: 'training_removed',
        changes_json: {
          'training' => {
            'topic' => @training_topic.name,
            'removed_by' => current_user.display_name,
            'removed_at' => Time.current.iso8601
          }
        },
        changed_at: Time.current
      )
      redirect_to train_member_path(user_id: @trainee.id), notice: "Removed #{@training_topic.name} training from #{@trainee.display_name}."
    else
      redirect_to train_member_path(user_id: @trainee.id), alert: "#{@trainee.display_name} was not trained in #{@training_topic.name}."
    end
  end

  private

  def require_trainer_or_admin
    return if current_user_admin?
    return if current_user.trainer_capabilities.any?

    redirect_to root_path, alert: "You don't have permission to train members."
  end

  def set_trainee
    @trainee = User.find(params[:user_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to train_member_path, alert: 'Member not found.'
  end

  def set_training_topic
    @training_topic = TrainingTopic.find(params[:topic_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to train_member_path, alert: 'Training topic not found.'
  end

  def trainable_topics_for_current_user
    if current_user_admin?
      TrainingTopic.order(:name)
    else
      current_user.training_topics.order(:name)
    end
  end

  def can_train_topic?(topic)
    return true if current_user_admin?

    current_user.training_topics.include?(topic)
  end
end
