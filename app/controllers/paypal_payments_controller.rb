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

  def test
    require 'set'
    
    # Only consider payments for $40 (with small tolerance for decimal precision)
    @payments_40 = PaypalPayment.where("amount >= ? AND amount <= ?", 39.99, 40.01)
    
    # Track unique email addresses that match User records
    unique_matched_emails = Set.new
    @unmatched_payments = []
    
    @payments_40.find_each do |payment|
      next if payment.payer_email.blank?
      
      normalized_email = payment.payer_email.to_s.strip.downcase
      next if normalized_email.blank?
      
      # Find users with matching email (primary or extra_emails)
      matching_users = User.where("LOWER(email) = ?", normalized_email)
      matching_users += User.where("EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)", normalized_email)
      matching_users = matching_users.uniq
      
      if matching_users.any?
        unique_matched_emails.add(normalized_email)
      else
        @unmatched_payments << {
          payment: payment,
          email: payment.payer_email,
          name: payment.payer_name
        }
      end
    end
    
    @unique_matched_email_count = unique_matched_emails.size
    @total_40_payments = @payments_40.count
  end
end

