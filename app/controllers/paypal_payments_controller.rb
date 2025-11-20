class PaypalPaymentsController < AuthenticatedController
  def index
    @payments = PaypalPayment.ordered
    @payment_count = @payments.count
    @total_amount = @payments.sum(:amount)
  end

  def show
    @payment = PaypalPayment.find(params[:id])

    # Find user by paypal_account_id matching this payment's payer_id
    @user_by_paypal_account_id = nil
    @user_by_paypal_account_id = User.where(paypal_account_id: @payment.payer_id).first if @payment.payer_id.present?

    # Get all users for the selection dropdown (if no match found)
    @all_users = User.ordered_by_display_name if @user_by_paypal_account_id.nil?
  end

  def link_user
    @payment = PaypalPayment.find(params[:id])
    user = User.find(params[:user_id])

    if @payment.payer_id.present?
      updates = { paypal_account_id: @payment.payer_id }

      # Set payment_type to 'paypal'
      updates[:payment_type] = 'paypal' if user.payment_type != 'paypal'

      # If membership_status is 'unknown', set it to 'basic'
      updates[:membership_status] = 'basic' if user.membership_status == 'unknown'

      user.update!(updates)
      redirect_to paypal_payment_path(@payment),
                  notice: "Linked to user #{user.display_name} and updated their PayPal account ID, payment type, and membership status."
    else
      redirect_to paypal_payment_path(@payment), alert: 'Cannot link: payment has no payer ID.'
    end
  end

  def sync
    Paypal::PaymentSyncJob.perform_later
    redirect_to paypal_payments_path, notice: 'PayPal payment sync has been scheduled.'
  end

  def test
    # Only consider payments for $40 (with small tolerance for decimal precision)
    @payments_40 = PaypalPayment.where(amount: 39.99..40.01)

    # Find payments that don't have a matching User by paypal_account_id
    @unmatched_payments = []

    @payments_40.find_each do |payment|
      next if payment.payer_id.blank?

      # Check if any User has this payer_id as their paypal_account_id
      matching_user = User.where(paypal_account_id: payment.payer_id).first

      unless matching_user
        @unmatched_payments << {
          payment: payment,
          email: payment.payer_email,
          name: payment.payer_name
        }
      end
    end

    @total_40_payments = @payments_40.count
    @matched_count = @total_40_payments - @unmatched_payments.count
  end
end
