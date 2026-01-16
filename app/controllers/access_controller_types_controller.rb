class AccessControllerTypesController < AdminController
  before_action :set_access_controller_type, only: [:edit, :update, :destroy, :toggle]

  def create
    @access_controller_type = AccessControllerType.new(access_controller_type_params)

    if @access_controller_type.save
      redirect_to access_controllers_path, notice: "Access controller type '#{@access_controller_type.name}' created."
    else
      redirect_to access_controllers_path, alert: @access_controller_type.errors.full_messages.to_sentence
    end
  end

  def edit; end

  def update
    if @access_controller_type.update(access_controller_type_params)
      redirect_to access_controllers_path, notice: "Access controller type '#{@access_controller_type.name}' updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @access_controller_type.name
    if @access_controller_type.destroy
      redirect_to access_controllers_path, notice: "Access controller type '#{name}' deleted."
    else
      redirect_to access_controllers_path, alert: @access_controller_type.errors.full_messages.to_sentence
    end
  end

  def toggle
    @access_controller_type.update!(enabled: !@access_controller_type.enabled)
    status = @access_controller_type.enabled? ? 'enabled' : 'disabled'
    redirect_to access_controllers_path, notice: "Access controller type '#{@access_controller_type.name}' #{status}."
  end

  private

  def set_access_controller_type
    @access_controller_type = AccessControllerType.find(params[:id])
  end

  def access_controller_type_params
    params.require(:access_controller_type).permit(:name, :script_path, :access_token, :enabled)
  end
end
