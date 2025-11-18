require 'set'

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

  def test
    @failures = []
    
    # Track which payments matched by email or name
    payments_matched_by_email = Set.new
    payments_matched_by_name = Set.new
    unique_matched_emails = Set.new
    unique_matched_names = Set.new
    unique_successful_payees = Set.new
    
    # Test email reconciliation
    RechargePayment.where.not(customer_email: nil).find_each do |payment|
      normalized_email = payment.customer_email.to_s.strip.downcase
      next if normalized_email.blank?
      
      # Find users with matching email (primary or extra_emails)
      matching_users = User.where("LOWER(email) = ?", normalized_email)
      matching_users += User.where("EXISTS (SELECT 1 FROM unnest(extra_emails) AS email WHERE LOWER(email) = ?)", normalized_email)
      matching_users = matching_users.uniq
      
      if matching_users.any?
        payments_matched_by_email.add(payment.id)
        unique_matched_emails.add(normalized_email)
        unique_successful_payees.add("email:#{normalized_email}")
      end
    end
    
    # Test name reconciliation
    RechargePayment.where.not(customer_name: nil).find_each do |payment|
      normalized_name = payment.customer_name.to_s.strip
      next if normalized_name.blank?
      
      normalized_name_lower = normalized_name.downcase
      
      # Find users with matching name (case-insensitive)
      matching_users = User.where("LOWER(full_name) = ?", normalized_name_lower)
      
      if matching_users.any?
        payments_matched_by_name.add(payment.id)
        unique_matched_names.add(normalized_name_lower)
        
        # Only add to successful payees if this payment didn't already match by email
        # (to avoid double-counting the same payee)
        unless payments_matched_by_email.include?(payment.id)
          unique_successful_payees.add("name:#{normalized_name_lower}")
        end
      end
    end
    
    # Find payments that matched neither email nor name
    all_payment_ids = Set.new(RechargePayment.pluck(:id))
    matched_payment_ids = payments_matched_by_email + payments_matched_by_name
    unmatched_payment_ids = all_payment_ids - matched_payment_ids
    
    # Track unique payees that failed (by email or name)
    unique_failed_payees = Set.new
    
    RechargePayment.where(id: unmatched_payment_ids).find_each do |payment|
      @failures << {
        payment: payment,
        email: payment.customer_email,
        name: payment.customer_name
      }
      
      # Track unique payees - prefer email, fall back to name
      if payment.customer_email.present?
        normalized_email = payment.customer_email.to_s.strip.downcase
        unique_failed_payees.add("email:#{normalized_email}") if normalized_email.present?
      elsif payment.customer_name.present?
        normalized_name = payment.customer_name.to_s.strip.downcase
        unique_failed_payees.add("name:#{normalized_name}") if normalized_name.present?
      end
    end
    
    @unique_email_successes = unique_matched_emails.size
    @unique_name_successes = unique_matched_names.size
    @unique_successful_payees = unique_successful_payees.size
    @total_failures = @failures.size
    @unique_failed_payees = unique_failed_payees.size
  end
end

