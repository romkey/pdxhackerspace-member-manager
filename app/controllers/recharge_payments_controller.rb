class RechargePaymentsController < AdminController
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

      # Copy email from payment if user doesn't have one
      if user.email.blank? && @payment.customer_email.present?
        updates[:email] = @payment.customer_email
      end

      # Set payment_type to 'recharge'
      updates[:payment_type] = 'recharge' if user.payment_type != 'recharge'

      # Find the most recent payment for this user (by recharge_customer_id)
      # Check both possible locations for customer_id in raw_attributes
      most_recent_payment = RechargePayment.where(status: 'SUCCESS')
                                           .where.not(processed_at: nil)
                                           .where(
                                             "(raw_attributes->>'customer_id')::text = ? OR (raw_attributes->'customer'->>'id')::text = ?",
                                             customer_id.to_s, customer_id.to_s
                                           )
                                           .order(processed_at: :desc)
                                           .first

      if most_recent_payment&.processed_at
        payment_date = most_recent_payment.processed_at.to_date

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
        # Reload the unmatched payments list
        all_unmatched_recharge = []
        RechargePayment.find_each do |payment|
          customer_id = extract_customer_id(payment)
          next if customer_id.blank?
          
          matching_user = User.where(recharge_customer_id: customer_id.to_s).first
          unless matching_user
            all_unmatched_recharge << {
              payment: payment,
              email: payment.customer_email,
              name: payment.customer_name,
              customer_id: customer_id
            }
          end
        end
        @unmatched_recharge_payments_count = all_unmatched_recharge.count
        @unmatched_recharge_payments = all_unmatched_recharge.first(20)
        @all_users = User.ordered_by_display_name
        
        respond_to do |format|
          format.html { redirect_to reports_path(tab: 'unmatched-recharge'), notice: "Linked to user #{user.display_name}." }
          format.turbo_stream
        end
      else
        redirect_to recharge_payment_path(@payment),
                    notice: "Linked to user #{user.display_name} and updated their Recharge customer ID, payment type, and membership status."
      end
    else
      if params[:from_reports] == 'true'
        redirect_to reports_path(tab: 'unmatched-recharge'), alert: 'Cannot link: payment has no customer ID.'
      else
        redirect_to recharge_payment_path(@payment), alert: 'Cannot link: payment has no customer ID.'
      end
    end
  end

  private

  def extract_customer_id(payment)
    return nil if payment.raw_attributes.blank?

    payment.raw_attributes.dig('customer', 'id') ||
      payment.raw_attributes['customer_id']
  end
end
