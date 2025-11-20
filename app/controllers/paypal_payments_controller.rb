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

      # Find the most recent payment for this user (by paypal_account_id)
      most_recent_payment = PaypalPayment.where(payer_id: @payment.payer_id)
                                         .where.not(transaction_time: nil)
                                         .order(transaction_time: :desc)
                                         .first

      if most_recent_payment&.transaction_time
        payment_date = most_recent_payment.transaction_time.to_date

        # Update last_payment_date to the most recent payment date
        updates[:last_payment_date] = payment_date if user.last_payment_date.nil? || payment_date > user.last_payment_date

        # If payment is within the last 32 days, mark user as active, set membership_status to basic, and dues_status to current
        if payment_date >= 32.days.ago.to_date
          updates[:active] = true unless user.active?
          updates[:membership_status] = 'basic' if user.membership_status != 'basic'
          updates[:dues_status] = 'current' if user.dues_status != 'current'
        end
      end

      user.update!(updates)
      
      # Redirect back to reports if coming from there, otherwise to payment detail page
      if params[:from_reports] == 'true'
        redirect_to reports_path(anchor: 'unmatched-paypal'),
                    notice: "Linked to user #{user.display_name} and updated their PayPal account ID, payment type, and membership status."
      else
        redirect_to paypal_payment_path(@payment),
                    notice: "Linked to user #{user.display_name} and updated their PayPal account ID, payment type, and membership status."
      end
    else
      if params[:from_reports] == 'true'
        redirect_to reports_path(anchor: 'unmatched-paypal'), alert: 'Cannot link: payment has no payer ID.'
      else
        redirect_to paypal_payment_path(@payment), alert: 'Cannot link: payment has no payer ID.'
      end
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
