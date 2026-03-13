class ApplicationFormPagesController < AdminController
  before_action :set_page, only: %i[edit update destroy]

  def index
    @pages = ApplicationFormPage.ordered.includes(:questions)
  end

  def new
    @page = ApplicationFormPage.new(position: (ApplicationFormPage.maximum(:position) || 0) + 1)
  end

  def create
    @page = ApplicationFormPage.new(page_params)
    if @page.save
      redirect_to application_form_pages_path, notice: 'Page added successfully.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @page.update(page_params)
      redirect_to application_form_pages_path, notice: 'Page updated successfully.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @page.destroy!
    redirect_to application_form_pages_path, notice: 'Page removed.'
  end

  private

  def set_page
    @page = ApplicationFormPage.find(params[:id])
  end

  def page_params
    params.require(:application_form_page).permit(:title, :description, :position)
  end
end
