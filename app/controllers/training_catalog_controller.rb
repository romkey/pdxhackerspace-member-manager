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
    @training_topics = visible_topics.order(:name)
    # Build a Set of topic ids that are currently open for member training requests.
    # We avoid the `available_for_member_requests` scope here because it combines
    # `distinct` with `order(:name)`, which Postgres rejects once we narrow the
    # select list (e.g. via `pluck(:id)`).
    @requestable_topic_ids = TrainingTopic.offered_for_members
                                          .joins(:trainer_capabilities)
                                          .distinct
                                          .pluck(:id)
                                          .to_set
  end

  def show
    @trainers = @training_topic.trainers.order(:full_name, :email)
    @trainees = User.where(id: @training_topic.trainings.select(:trainee_id).distinct)
                    .order(:full_name, :email)
    @topic_links = @training_topic.links.order(:title)
    @topic_documents = visible_documents_for(@training_topic)
    @requestable = @training_topic.offered_to_members? &&
                   @training_topic.trainer_capabilities.exists?
  end

  private

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
