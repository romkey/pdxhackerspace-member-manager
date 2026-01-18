class AccessControllersController < AdminController
  before_action :set_access_controller, only: [:show, :edit, :update, :destroy, :toggle, :sync, :run_verb]

  def index
    @access_controllers = AccessController.includes(:access_controller_type).ordered
  end

  def show; end

  def new
    @access_controller = AccessController.new
    @access_controller_types = AccessControllerType.ordered
  end

  def create
    @access_controller = AccessController.new(access_controller_params)

    if @access_controller.save
      redirect_to access_controllers_path, notice: "Access controller '#{@access_controller.name}' created."
    else
      @access_controller_types = AccessControllerType.ordered
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @access_controller_types = AccessControllerType.ordered
  end

  def update
    if @access_controller.update(access_controller_params)
      redirect_to access_controllers_path, notice: "Access controller '#{@access_controller.name}' updated."
    else
      @access_controller_types = AccessControllerType.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @access_controller.name
    @access_controller.destroy!
    redirect_to access_controllers_path, notice: "Access controller '#{name}' deleted."
  end

  def toggle
    @access_controller.update!(enabled: !@access_controller.enabled)
    status = @access_controller.enabled? ? 'enabled' : 'disabled'
    redirect_to access_controllers_path, notice: "Access controller '#{@access_controller.name}' #{status}."
  end

  def sync
    if @access_controller.enabled?
      AccessControllerSyncJob.perform_later(@access_controller.id)
      redirect_to access_controllers_path, notice: "Sync started for '#{@access_controller.name}'."
    else
      redirect_to access_controllers_path, alert: "Access controller '#{@access_controller.name}' is disabled."
    end
  end

  def run_verb
    verb = params[:verb].to_s.strip
    verbs = Array(@access_controller.access_controller_type&.verbs)

    if verb.blank? || !verbs.include?(verb)
      redirect_to access_controllers_path, alert: 'Invalid access controller verb.'
      return
    end

    if @access_controller.enabled?
      AccessControllerVerbJob.perform_later(@access_controller.id, verb)
      redirect_to access_controllers_path, notice: "Command '#{verb}' started for '#{@access_controller.name}'."
    else
      redirect_to access_controllers_path, alert: "Access controller '#{@access_controller.name}' is disabled."
    end
  end

  def sync_all
    enabled = AccessController.enabled
    enabled.find_each { |controller| AccessControllerSyncJob.perform_later(controller.id) }
    redirect_to access_controllers_path, notice: "Sync started for #{enabled.count} access controller(s)."
  end

  private

  def set_access_controller
    @access_controller = AccessController.includes(:access_controller_type).find(params[:id])
  end

  def access_controller_params
    params.require(:access_controller).permit(:name, :hostname, :description, :enabled, :display_order, :access_controller_type_id)
  end
end
