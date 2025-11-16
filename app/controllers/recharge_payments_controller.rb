class RechargePaymentsController < AuthenticatedController
  def index
    @payments = RechargePayment.ordered
    @payment_count = @payments.count
    @total_amount = @payments.sum(:amount)
  end

  def show
    @payment = RechargePayment.find(params[:id])
  end

  def sync
    Recharge::PaymentSyncJob.perform_later
    redirect_to recharge_payments_path, notice: "Recharge payment sync has been scheduled."
  end
end

