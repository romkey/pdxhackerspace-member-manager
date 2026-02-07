class DocumentsController < AdminController
  skip_before_action :require_admin!, only: [:download]
  before_action :require_authenticated_user!, only: [:download]
  before_action :set_document, only: [:show, :edit, :update, :destroy, :download]

  def index
    @documents = Document.ordered.includes(:training_topics)
  end

  def show
  end

  def new
    @document = Document.new
    @training_topics = TrainingTopic.order(:name)
  end

  def create
    @document = Document.new(document_params)

    if @document.save
      redirect_to documents_path, notice: 'Document created successfully.'
    else
      @training_topics = TrainingTopic.order(:name)
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @training_topics = TrainingTopic.order(:name)
  end

  def update
    if @document.update(document_params)
      redirect_to documents_path, notice: 'Document updated successfully.'
    else
      @training_topics = TrainingTopic.order(:name)
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @document.destroy
    redirect_to documents_path, notice: 'Document deleted successfully.'
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
    document.training_topics.any? do |topic|
      Training.exists?(trainee: user, training_topic: topic)
    end
  end

  def set_document
    @document = Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:title, :file, :show_on_all_profiles, training_topic_ids: [])
  end
end
