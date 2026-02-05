class DocumentsController < AdminController
  before_action :set_document, only: [:show, :edit, :update, :destroy]

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

  private

  def set_document
    @document = Document.find(params[:id])
  end

  def document_params
    params.require(:document).permit(:title, :file, :show_on_all_profiles, training_topic_ids: [])
  end
end
