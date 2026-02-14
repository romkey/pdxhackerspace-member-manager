class DocumentsController < AuthenticatedController
  before_action :require_admin!, only: [:index]
  before_action :set_document, only: [:show, :edit, :update, :destroy, :download]
  before_action :require_admin_or_topic_trainer!, only: [:new, :create]
  before_action :require_admin_or_document_trainer!, only: [:show, :edit, :update, :destroy]

  def index
    @documents = Document.ordered.includes(:training_topics)
  end

  def show
  end

  def new
    @document = Document.new
    @training_topics = available_training_topics
    # Pre-select the topic if coming from a topic page
    if params[:training_topic_id].present?
      @document.training_topic_ids = [params[:training_topic_id]]
    end
  end

  def create
    @document = Document.new(document_params)

    # Non-admins cannot set show_on_all_profiles
    @document.show_on_all_profiles = false unless current_user_admin?

    # Non-admins can only associate with their trainable topics
    unless current_user_admin?
      allowed_ids = current_user.training_topics.pluck(:id)
      @document.training_topic_ids = @document.training_topic_ids & allowed_ids
    end

    if @document.save
      redirect_path = if params[:return_to_topic].present?
                        edit_training_topic_path(params[:return_to_topic])
                      else
                        documents_path
                      end
      redirect_to redirect_path, notice: 'Document created successfully.'
    else
      @training_topics = available_training_topics
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @training_topics = available_training_topics
  end

  def update
    update_params = document_params

    # Non-admins cannot change show_on_all_profiles
    unless current_user_admin?
      update_params.delete(:show_on_all_profiles)
      # Non-admins can only associate with their trainable topics
      if update_params[:training_topic_ids].present?
        allowed_ids = current_user.training_topics.pluck(:id)
        update_params[:training_topic_ids] = update_params[:training_topic_ids].select { |id| id.blank? || allowed_ids.include?(id.to_i) }
      end
    end

    if @document.update(update_params)
      redirect_path = if params[:return_to_topic].present?
                        edit_training_topic_path(params[:return_to_topic])
                      else
                        documents_path
                      end
      redirect_to redirect_path, notice: 'Document updated successfully.'
    else
      @training_topics = available_training_topics
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    return_path = if params[:return_to_topic].present?
                    edit_training_topic_path(params[:return_to_topic])
                  else
                    documents_path
                  end
    @document.destroy
    redirect_to return_path, notice: 'Document deleted successfully.'
  end

  # Protected download - requires authentication
  # Checks if user is allowed to access this document
  def download
    # Admins can download any document
    unless true_user_admin? || user_can_access_document?(current_user, @document)
      redirect_to root_path, alert: 'You do not have access to this document.'
      return
    end

    send_data @document.file.download,
              filename: @document.file.filename.to_s,
              type: @document.file.content_type,
              disposition: 'attachment'
  end

  private

  def user_can_access_document?(user, document)
    return false unless user

    # Document is shown on all profiles
    return true if document.show_on_all_profiles?

    # Check if user is trained in any of the document's topics
    return true if document.training_topics.any? { |topic| Training.exists?(trainee: user, training_topic: topic) }

    # Check if user is a trainer for any of the document's topics
    return true if document.training_topics.any? { |topic| TrainerCapability.exists?(user: user, training_topic: topic) }

    false
  end

  # Trainers can manage documents associated with their trainable topics
  def trainer_for_document?(document)
    return false unless current_user
    return false if document.training_topics.empty?

    trainable_topic_ids = current_user.training_topics.pluck(:id)
    (document.training_topic_ids & trainable_topic_ids).any?
  end

  def require_admin_or_topic_trainer!
    return if current_user_admin?
    return if current_user&.trainer_capabilities&.any?

    redirect_to root_path, alert: "You don't have permission to manage documents."
  end

  def require_admin_or_document_trainer!
    return if current_user_admin?
    return if trainer_for_document?(@document)

    redirect_to root_path, alert: "You don't have permission to manage this document."
  end

  def available_training_topics
    if current_user_admin?
      TrainingTopic.order(:name)
    else
      current_user.training_topics.order(:name)
    end
  end

  def set_document
    @document = Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:title, :file, :show_on_all_profiles, training_topic_ids: [])
  end
end
