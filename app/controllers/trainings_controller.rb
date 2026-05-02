class TrainingsController < AuthenticatedController
  before_action :require_trainer_or_admin
  before_action :prepare_record_training_form, only: :record
  before_action :set_trainee,
                only: %i[add_training remove_training add_trainer_capability remove_trainer_capability]
  before_action :set_training_topic,
                only: %i[add_training remove_training add_trainer_capability remove_trainer_capability]

  def index = redirect_to(record_training_path)

  def record; end

  def create_bulk
    training_topic = TrainingTopic.find(params[:training_topic_id])
    unless can_train_topic?(training_topic)
      redirect_to record_training_path, alert: "You don't have permission to train #{training_topic.name}."
      return
    end

    trainee_ids = Array(params[:trainee_ids]).compact_blank.uniq
    if trainee_ids.empty?
      redirect_to record_training_path, alert: 'Add at least one member before recording training.'
      return
    end

    trainer = selected_trainer_for_recording
    trained_at = parsed_trained_at
    result = TrainingRecorder.new(
      current_user: current_user,
      training_topic: training_topic,
      trainee_ids: trainee_ids,
      trainer: trainer,
      trained_at: trained_at
    ).call

    if result.recorded_count.zero?
      redirect_to record_training_path,
                  alert: 'No training events were recorded. Everyone selected was already trained ' \
                         'or could not be trained.'
      return
    end

    skipped_message = result.skipped_count.positive? ? " #{result.skipped_count} skipped." : ''
    event_label = 'event'.pluralize(result.recorded_count)
    redirect_to training_catalog_path,
                notice: "Recorded #{result.recorded_count} training #{event_label} " \
                        "for #{training_topic.name}.#{skipped_message}"
  rescue ActiveRecord::RecordNotFound
    redirect_to record_training_path, alert: 'Training topic not found.'
  end

  def add_training
    unless can_train_topic?(@training_topic)
      redirect_to redirect_back_path, alert: "You don't have permission to train #{@training_topic.name}."
      return
    end

    # Check if training already exists
    existing = Training.find_by(trainee: @trainee, training_topic: @training_topic)
    if existing
      redirect_to redirect_back_path(user_id: @trainee.id),
                  notice: "#{@trainee.display_name} is already trained in #{@training_topic.name}."
      return
    end

    result = TrainingRecorder.new(
      current_user: current_user,
      training_topic: @training_topic,
      trainee_ids: [@trainee.id.to_s],
      trainer: current_user,
      trained_at: Time.current
    ).call

    if result.recorded_count.positive?
      redirect_to redirect_back_path(user_id: @trainee.id),
                  notice: "#{@trainee.display_name} has been marked as trained in #{@training_topic.name}."
    else
      redirect_to redirect_back_path(user_id: @trainee.id),
                  alert: "Failed to add training for #{@trainee.display_name}."
    end
  end

  def remove_training
    unless can_train_topic?(@training_topic)
      redirect_to train_member_path, alert: "You don't have permission to manage #{@training_topic.name} training."
      return
    end

    trainings = Training.where(trainee: @trainee, training_topic: @training_topic)
    count = trainings.count

    if count.positive?
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
        changed_at: Time.current,
        highlight: true
      )
      redirect_to train_member_path(user_id: @trainee.id),
                  notice: "Removed #{@training_topic.name} training from #{@trainee.display_name}."
    else
      redirect_to train_member_path(user_id: @trainee.id),
                  alert: "#{@trainee.display_name} was not trained in #{@training_topic.name}."
    end
  end

  def add_trainer_capability
    unless current_user_admin?
      redirect_to train_member_path, alert: 'Only admins can manage trainer capabilities.'
      return
    end

    existing = TrainerCapability.find_by(user: @trainee, training_topic: @training_topic)
    if existing
      redirect_to train_member_path(user_id: @trainee.id),
                  notice: "#{@trainee.display_name} can already train #{@training_topic.name}."
      return
    end

    capability = TrainerCapability.new(user: @trainee, training_topic: @training_topic)

    if capability.save
      # Also mark them as trained if not already
      unless Training.exists?(trainee: @trainee, training_topic: @training_topic)
        Training.create!(
          trainee: @trainee,
          trainer: current_user,
          training_topic: @training_topic,
          trained_at: Time.current
        )
      end

      Journal.create!(
        user: @trainee,
        actor_user: current_user,
        action: 'trainer_capability_added',
        changes_json: {
          'trainer_capability' => {
            'topic' => @training_topic.name,
            'granted_by' => current_user.display_name,
            'granted_at' => Time.current.iso8601
          }
        },
        changed_at: Time.current,
        highlight: true
      )
      if @trainee.email.present?
        QueuedMail.enqueue(:trainer_capability_granted, @trainee,
                           reason: "Can now train #{@training_topic.name}",
                           training_topic: @training_topic.name)
      end
      redirect_to train_member_path(user_id: @trainee.id),
                  notice: "#{@trainee.display_name} can now train others in #{@training_topic.name}."
    else
      redirect_to train_member_path(user_id: @trainee.id),
                  alert: "Failed to add trainer capability: #{capability.errors.full_messages.join(', ')}"
    end
  end

  def remove_trainer_capability
    unless current_user_admin?
      redirect_to train_member_path, alert: 'Only admins can manage trainer capabilities.'
      return
    end

    capability = TrainerCapability.find_by(user: @trainee, training_topic: @training_topic)

    if capability&.destroy
      Journal.create!(
        user: @trainee,
        actor_user: current_user,
        action: 'trainer_capability_removed',
        changes_json: {
          'trainer_capability' => {
            'topic' => @training_topic.name,
            'revoked_by' => current_user.display_name,
            'revoked_at' => Time.current.iso8601
          }
        },
        changed_at: Time.current,
        highlight: true
      )
      redirect_to train_member_path(user_id: @trainee.id),
                  notice: "Removed #{@training_topic.name} trainer capability from #{@trainee.display_name}."
    else
      redirect_to train_member_path(user_id: @trainee.id),
                  alert: "#{@trainee.display_name} did not have trainer capability for #{@training_topic.name}."
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
    current_user_admin? ? TrainingTopic.order(:name) : current_user.training_topics.order(:name)
  end

  def can_train_topic?(topic)
    return true if current_user_admin?

    current_user.training_topics.include?(topic)
  end

  def prepare_record_training_form
    @trainable_topics = trainable_topics_for_current_user
    @trainer_options = trainer_options_for_recording
    @recording_users = recording_user_options
    @initial_trainee_ids = Array(params[:member].presence || params[:user_id].presence).compact_blank.map(&:to_s)
  end

  def trainer_options_for_recording
    return [current_user] unless current_user_admin?

    trainer_ids = TrainerCapability.distinct.pluck(:user_id)
    trainer_ids << current_user.id
    User.where(id: trainer_ids.uniq).ordered_by_display_name
  end

  def recording_user_options
    users = User.ordered_by_display_name.to_a
    trained_topic_ids_by_user = Training.where(trainee_id: users.map(&:id))
                                        .pluck(:trainee_id, :training_topic_id)
                                        .each_with_object(
                                          Hash.new { |hash, key| hash[key] = [] }
                                        ) do |(trainee_id, topic_id), grouped|
      grouped[trainee_id] << topic_id
    end

    users.map do |user|
      {
        id: user.id,
        name: user.display_name,
        email: user.email,
        username: user.username,
        active: user.active?,
        banned: user.banned?,
        trained_topic_ids: trained_topic_ids_by_user[user.id]
      }
    end
  end

  def selected_trainer_for_recording
    return current_user unless current_user_admin?

    trainer_options_for_recording.find { |trainer| trainer.id.to_s == params[:trainer_id].to_s } || current_user
  end

  def parsed_trained_at
    Date.iso8601(params[:trained_at].presence || Date.current.iso8601).in_time_zone
  rescue ArgumentError
    Date.current.in_time_zone
  end

  def redirect_back_path(user_id: nil)
    if params[:return_to] == 'topic' && @training_topic
      edit_training_topic_path(@training_topic)
    elsif user_id
      train_member_path(user_id: user_id)
    else
      train_member_path
    end
  end
end
