class PaymentProcessorsController < AdminController
  before_action :set_payment_processor, only: [:show, :edit, :update, :toggle, :refresh_stats]

  def index
    @payment_processors = PaymentProcessor.ordered
  end

  def show; end

  def edit; end

  def update
    if @payment_processor.update(payment_processor_params)
      redirect_to payment_processors_path, notice: "#{@payment_processor.name} settings updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def toggle
    @payment_processor.update!(enabled: !@payment_processor.enabled)
    @payment_processor.update!(sync_status: 'disabled') unless @payment_processor.enabled?
    status = @payment_processor.enabled? ? 'enabled' : 'disabled'
    redirect_to payment_processors_path, notice: "#{@payment_processor.name} has been #{status}."
  end

  def refresh_stats
    @payment_processor.check_api_configuration!
    @payment_processor.refresh_statistics!
    redirect_to payment_processors_path, notice: "#{@payment_processor.name} statistics refreshed."
  end

  def refresh_all
    PaymentProcessor.find_each do |processor|
      processor.check_api_configuration!
      processor.refresh_statistics!
    end
    redirect_to payment_processors_path, notice: "All payment processor statistics refreshed."
  end

  def seed
    PaymentProcessor.seed_defaults!
    redirect_to payment_processors_path, notice: "Payment processors seeded."
  end

  private

  def set_payment_processor
    @payment_processor = PaymentProcessor.find(params[:id])
  end

  def payment_processor_params
    params.require(:payment_processor).permit(:name, :enabled, :display_order, :payment_link, :webhook_url, :notes)
  end
end
