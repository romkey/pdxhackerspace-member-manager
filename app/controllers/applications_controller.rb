class ApplicationsController < AuthenticatedController
  def index
    @applications = Application.includes(:application_groups).order(:name)
  end

  def show
    @application = Application.includes(application_groups: :users).find(params[:id])
  end

  def new
    @application = Application.new(
      authentik_prefix: 'ctrlh:app',
      internal_url: 'http://',
      external_url: 'https://'
    )
  end

  def edit
    @application = Application.find(params[:id])
  end

  def create
    @application = Application.new(application_params)

    if @application.save
      redirect_to @application, notice: 'Application created successfully.'
    else
      flash.now[:alert] = 'Unable to create application.'
      render :new, status: :unprocessable_content
    end
  end

  def update
    @application = Application.find(params[:id])

    if @application.update(application_params)
      redirect_to @application, notice: 'Application updated successfully.'
    else
      flash.now[:alert] = 'Unable to update application.'
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @application = Application.find(params[:id])
    @application.destroy
    redirect_to applications_path, notice: 'Application deleted successfully.'
  end

  private

  def application_params
    params.require(:application).permit(:name, :internal_url, :external_url, :authentik_prefix)
  end
end
