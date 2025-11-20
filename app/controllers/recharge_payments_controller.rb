class RechargePaymentsController < AuthenticatedController
  def index
    @payments = RechargePayment.ordered
    @payment_count = @payments.count
    @total_amount = @payments.sum(:amount)
  end

  def show
    @payment = RechargePayment.find(params[:id])

    # Try to find user by recharge_customer_id
    @customer_id = extract_customer_id(@payment)
    @user_by_customer_id = nil
    @user_by_customer_id = User.where(recharge_customer_id: @customer_id.to_s).first if @customer_id.present?

    # Get all users for the selection dropdown (if no match found)
    @all_users = User.ordered_by_display_name if @user_by_customer_id.nil?
  end

  def sync
    Recharge::PaymentSyncJob.perform_later
    redirect_to recharge_payments_path, notice: 'Recharge payment sync has been scheduled.'
  end

  def test
    # Find payments that don't have a matching User by recharge_customer_id
    @unmatched_payments = []

    RechargePayment.find_each do |payment|
      customer_id = extract_customer_id(payment)
      next if customer_id.blank?

      # Check if any User has this customer_id as their recharge_customer_id
      matching_user = User.where(recharge_customer_id: customer_id.to_s).first

      unless matching_user
        @unmatched_payments << {
          payment: payment,
          email: payment.customer_email,
          name: payment.customer_name,
          customer_id: customer_id
        }
      end
    end

    @total_payments = RechargePayment.count
    @matched_count = @total_payments - @unmatched_payments.count
  end

  def link_user
    @payment = RechargePayment.find(params[:id])
    user = User.find(params[:user_id])

    customer_id = extract_customer_id(@payment)

    if customer_id.present?
      updates = { recharge_customer_id: customer_id.to_s }

      # Set payment_type to 'recharge'
      updates[:payment_type] = 'recharge' if user.payment_type != 'recharge'

      # If membership_status is 'unknown', set it to 'basic'
      updates[:membership_status] = 'basic' if user.membership_status == 'unknown'

      user.update!(updates)
      redirect_to recharge_payment_path(@payment),
                  notice: "Linked to user #{user.display_name} and updated their Recharge customer ID, payment type, and membership status."
    else
      redirect_to recharge_payment_path(@payment), alert: 'Cannot link: payment has no customer ID.'
    end
  end

  private

  def extract_customer_id(payment)
    return nil if payment.raw_attributes.blank?

    payment.raw_attributes.dig('customer', 'id') ||
      payment.raw_attributes['customer_id']
  end
end
