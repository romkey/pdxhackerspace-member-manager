class PaypalPaymentsController < AuthenticatedController
  def index
    @payments = PaypalPayment.ordered
    @payment_count = @payments.count
    @total_amount = @payments.sum(:amount)
  end

  def show
    @payment = PaypalPayment.find(params[:id])
  end

  def sync
    Paypal::PaymentSyncJob.perform_later
    redirect_to paypal_payments_path, notice: "PayPal payment sync has been scheduled."
  end
end

