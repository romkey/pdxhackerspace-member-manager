class PaypalPaymentsController < AdminController
  def index
    # Start with all payments for counts
    all_payments = PaypalPayment.all

    # Calculate counts
    @total_count = all_payments.count
    @linked_count = all_payments.where.not(user_id: nil).count
    # Unlinked excludes dont_link payments
    @unlinked_count = all_payments.where(user_id: nil, dont_link: false).count
    @dont_link_count = all_payments.where(dont_link: true).count

    # Build filtered query
    @payments = all_payments

    # Apply linked/unlinked filter
    case params[:linked]
    when 'yes'
      @payments = @payments.where.not(user_id: nil)
    when 'no'
      # Unlinked excludes dont_link payments
      @payments = @payments.where(user_id: nil, dont_link: false)
    when 'dont_link'
      @payments = @payments.where(dont_link: true)
    end

    @payments = @payments.ordered
    @payment_count = @payments.count
    @total_amount = @payments.sum(:amount)

    # Track filter state
    @filter_active = params[:linked].present?
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
      # Link the payment to the user
      # The PaypalPayment after_save callback will call user.on_paypal_payment_linked
      # to handle payer ID, email, payment type, and membership status
      @payment.update!(user_id: user.id)
      
      # Redirect back to reports if coming from there, otherwise to payment detail page
      if params[:from_reports] == 'true'
        # Reload the unmatched payments list
        all_unmatched_paypal = []
        PaypalPayment.where.not(payer_id: nil).where(user_id: nil).find_each do |payment|
          matching_user = User.where(paypal_account_id: payment.payer_id).first
          unless matching_user
            all_unmatched_paypal << {
              payment: payment,
              email: payment.payer_email,
              name: payment.payer_name
            }
          end
        end
        @unmatched_paypal_payments_count = all_unmatched_paypal.count
        @unmatched_paypal_payments = all_unmatched_paypal.first(20)
        @all_users = User.ordered_by_display_name
        
        respond_to do |format|
          format.html { redirect_to reports_path(tab: 'unmatched-paypal'), notice: "Linked to user #{user.display_name}." }
          format.turbo_stream
        end
      else
        redirect_to paypal_payment_path(@payment),
                    notice: "Linked to user #{user.display_name} and updated their PayPal account ID, payment type, and membership status."
      end
    else
      if params[:from_reports] == 'true'
        redirect_to reports_path(tab: 'unmatched-paypal'), alert: 'Cannot link: payment has no payer ID.'
      else
        redirect_to paypal_payment_path(@payment), alert: 'Cannot link: payment has no payer ID.'
      end
    end
  end

  def toggle_dont_link
    @payment = PaypalPayment.find(params[:id])
    new_value = !@payment.dont_link
    @payment.update!(dont_link: new_value)

    notice = new_value ? "Payment marked as Don't Link." : "Payment unmarked as Don't Link."
    redirect_to paypal_payment_path(@payment), notice: notice
  end

  def create_member
    @payment = PaypalPayment.find(params[:id])

    # Only allow creating member for unlinked payments
    if @payment.user_id.present?
      redirect_to paypal_payment_path(@payment), alert: 'Payment is already linked to a member.'
      return
    end

    # Create new user from payment data
    user = User.new(
      full_name: @payment.payer_name,
      email: @payment.payer_email,
      paypal_account_id: @payment.payer_id,
      payment_type: 'paypal',
      membership_status: 'unknown',
      dues_status: 'unknown',
      active: false
    )

    if user.save
      # Link the payment to the new user (this will trigger the callback)
      @payment.update!(user_id: user.id)
      redirect_to user_path(user), notice: "Created member #{user.display_name} and linked payment."
    else
      redirect_to paypal_payment_path(@payment), alert: "Failed to create member: #{user.errors.full_messages.join(', ')}"
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

  def export
    # Export all PayPal payments as complete JSON backup
    payments_data = PaypalPayment.all.map do |payment|
      payment_data = {
        paypal_id: payment.paypal_id,
        status: payment.status,
        amount: payment.amount&.to_s, # Convert BigDecimal to string for JSON
        currency: payment.currency,
        transaction_time: payment.transaction_time&.iso8601,
        transaction_type: payment.transaction_type,
        payer_email: payment.payer_email,
        payer_name: payment.payer_name,
        payer_id: payment.payer_id,
        raw_attributes: payment.raw_attributes,
        last_synced_at: payment.last_synced_at&.iso8601,
        created_at: payment.created_at.iso8601,
        updated_at: payment.updated_at.iso8601
      }

      # Export user relationship by identifier
      if payment.user
        payment_data[:user_email] = payment.user.email
        payment_data[:user_authentik_id] = payment.user.authentik_id
      end

      payment_data
    end

    export_data = {
      version: '1.0',
      exported_at: Time.current.iso8601,
      count: payments_data.count,
      payments: payments_data
    }

    send_data JSON.pretty_generate(export_data),
              type: 'application/json',
              disposition: "attachment; filename=paypal_payments_backup_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
  end

  def import
    if params[:file].blank?
      redirect_to paypal_payments_path, alert: 'No file provided.'
      return
    end

    begin
      json_data = JSON.parse(params[:file].read)
      
      unless json_data.is_a?(Hash) && json_data['payments'].is_a?(Array)
        redirect_to paypal_payments_path, alert: 'Invalid JSON format. Expected object with "payments" array.'
        return
      end

      imported_count = 0
      updated_count = 0
      skipped_count = 0
      errors = []

      ActiveRecord::Base.transaction do
        json_data['payments'].each do |payment_data|
          begin
            # Find or initialize payment by paypal_id
            payment = PaypalPayment.find_or_initialize_by(paypal_id: payment_data['paypal_id'])

            # Update all attributes
            payment.status = payment_data['status']
            
            # Handle amount conversion (can be string or number)
            if payment_data['amount'].present?
              payment.amount = BigDecimal(payment_data['amount'].to_s)
            end
            
            payment.currency = payment_data['currency']
            
            # Parse timestamps
            if payment_data['transaction_time'].present?
              payment.transaction_time = Time.parse(payment_data['transaction_time'])
            end
            
            payment.transaction_type = payment_data['transaction_type']
            payment.payer_email = payment_data['payer_email']
            payment.payer_name = payment_data['payer_name']
            payment.payer_id = payment_data['payer_id']
            payment.raw_attributes = payment_data['raw_attributes'] || {}
            
            if payment_data['last_synced_at'].present?
              payment.last_synced_at = Time.parse(payment_data['last_synced_at'])
            end

            # Restore user relationship
            if payment_data['user_email'].present? || payment_data['user_authentik_id'].present?
              user = nil
              
              # Try to find by email first
              if payment_data['user_email'].present?
                user = User.find_by('LOWER(email) = ?', payment_data['user_email'].to_s.strip.downcase)
              end
              
              # Try to find by authentik_id if not found
              if user.nil? && payment_data['user_authentik_id'].present?
                user = User.find_by(authentik_id: payment_data['user_authentik_id'])
              end
              
              payment.user = user if user
            end

            was_new = payment.new_record?
            
            # Save the payment first
            payment.save!
            
            # Restore timestamps after save (Rails allows setting these directly)
            if payment_data['created_at'].present?
              payment.update_column(:created_at, Time.parse(payment_data['created_at']))
            end
            if payment_data['updated_at'].present?
              payment.update_column(:updated_at, Time.parse(payment_data['updated_at']))
            end

            if was_new
              imported_count += 1
            else
              updated_count += 1
            end
          rescue => e
            skipped_count += 1
            errors << "Payment #{payment_data['paypal_id']}: #{e.message}"
            Rails.logger.error("Failed to import PayPal payment #{payment_data['paypal_id']}: #{e.message}")
          end
        end
      end

      # Record CSV import in processor
      processor = PaymentProcessor.for('paypal')
      processor.record_csv_import!

      notice_parts = ["Import complete: #{imported_count} imported, #{updated_count} updated"]
      notice_parts << "#{skipped_count} skipped" if skipped_count > 0
      notice = notice_parts.join(', ')
      
      if errors.any?
        notice += ". Errors: #{errors.first(5).join('; ')}"
        notice += " (#{errors.count - 5} more)" if errors.count > 5
      end

      redirect_to paypal_payments_path, notice: notice
    rescue JSON::ParserError => e
      redirect_to paypal_payments_path, alert: "Invalid JSON: #{e.message}"
    rescue => e
      redirect_to paypal_payments_path, alert: "Import failed: #{e.message}"
    end
  end
end
