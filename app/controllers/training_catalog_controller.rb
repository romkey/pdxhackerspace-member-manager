# Member-facing catalog of training topics.
#
# Admins see every topic; non-admins only see topics with
# `offered_to_members = true`. Each topic has a detail page showing
# trainers, trainees, and training materials (links + documents).
# From the detail page, both admins and non-admins can request training
# for any topic that is offered to members and has at least one trainer.
class TrainingCatalogController < AuthenticatedController
  before_action :set_training_topic, only: :show
  before_action :authorize_topic_visibility!, only: :show

  def index
    topics = visible_topics.order(:name).to_a
    prepare_training_catalog_counts(topics)
    @training_topics = filtered_training_topics(topics)

    # Topics that are currently open for member training requests: offered to
    # members and with at least one active trainer. `reorder(nil)` drops the
    # scope's `order(:name)` so Postgres accepts the `DISTINCT id` select.
    @requestable_topic_ids = TrainingTopic.available_for_member_requests
                                          .reorder(nil)
                                          .pluck(:id)
                                          .to_set
    @requestable_topic_ids -= @trained_topic_ids
  end

  def show
    @trainers = @training_topic.trainers.active.order(:full_name, :email)
    @trainees = User.where(id: @training_topic.trainings.select(:trainee_id).distinct)
                    .order(:full_name, :email)
    @topic_links = @training_topic.links.order(:title)
    @topic_documents = visible_documents_for(@training_topic)
    @requestable = @training_topic.offered_to_members? &&
                   @training_topic.trainers.active.exists?
  end

  private

  def prepare_training_catalog_counts(topics)
    topic_ids = topics.map(&:id)
    @all_topic_count = topics.size
    @topic_trainer_counts = grouped_training_count(TrainerCapability, topic_ids, :user_id)
    @topic_trained_counts = grouped_training_count(Training, topic_ids, :trainee_id)
    @trained_topic_ids = Training.where(trainee: current_user).pluck(:training_topic_id).to_set
    @needs_trainers_count = topics.count { |topic| needs_trainers?(topic) }
    @offered_topic_count = topics.count(&:offered_to_members?)
  end

  def grouped_training_count(model, topic_ids, column)
    model.where(training_topic_id: topic_ids)
         .group(:training_topic_id)
         .distinct
         .count(column)
  end

  def filtered_training_topics(topics)
    case params[:training_filter]
    when 'offered'
      topics.select(&:offered_to_members?)
    when 'needs_trainers'
      topics.select { |topic| needs_trainers?(topic) }
    else
      topics
    end
  end

  def needs_trainers?(topic)
    topic.offered_to_members? && @topic_trainer_counts[topic.id].to_i.zero?
  end

  def set_training_topic
    @training_topic = TrainingTopic.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to training_catalog_path, alert: 'Training topic not found.'
  end

  def authorize_topic_visibility!
    return if current_user_admin?
    return if @training_topic.offered_to_members?

    redirect_to training_catalog_path, alert: 'That training topic is not available.'
  end

  def visible_topics
    return TrainingTopic.all if current_user_admin?

    TrainingTopic.offered_for_members
  end

  # Non-admins may only see documents they are allowed to download
  # (trained in the topic, a trainer for it, or marked `show_on_all_profiles`).
  def visible_documents_for(topic)
    documents = topic.documents.ordered
    return documents if current_user_admin?

    trained = Training.exists?(trainee: current_user, training_topic: topic)
    trainer = TrainerCapability.exists?(user: current_user, training_topic: topic)
    return documents if trained || trainer

    documents.where(show_on_all_profiles: true)
  end
end
