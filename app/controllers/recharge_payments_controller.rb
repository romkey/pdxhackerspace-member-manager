class RechargePaymentsController < AdminController
  def index
    # Start with all payments for counts
    all_payments = RechargePayment.all

    # Calculate counts
    @total_count = all_payments.count
    @linked_count = all_payments.where.not(user_id: nil).count
    @unlinked_count = all_payments.where(user_id: nil).count

    # Build filtered query
    @payments = all_payments

    # Apply linked/unlinked filter
    case params[:linked]
    when 'yes'
      @payments = @payments.where.not(user_id: nil)
    when 'no'
      @payments = @payments.where(user_id: nil)
    end

    @payments = @payments.ordered
    @payment_count = @payments.count
    @total_amount = @payments.sum(:amount)

    # Track filter state
    @filter_active = params[:linked].present?
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

    customer_id = @payment.customer_id || extract_customer_id(@payment)

    if customer_id.present?
      # Link the payment to the user
      # The RechargePayment after_save callback will call user.on_recharge_payment_linked
      # to handle customer ID, email, payment type, and membership status
      @payment.update!(user_id: user.id)
      
      # Redirect back to reports if coming from there, otherwise to payment detail page
      if params[:from_reports] == 'true'
        # Reload the unmatched payments count
        @unmatched_recharge_payments_count = RechargePayment.unmatched.count
        @unmatched_recharge_payments = RechargePayment.unmatched.ordered.limit(20).map do |payment|
          { payment: payment, email: payment.customer_email, name: payment.customer_name, customer_id: payment.customer_id }
        end
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

  def export
    # Export all Recharge payments as complete JSON backup
    payments_data = RechargePayment.all.map do |payment|
      payment_data = {
        recharge_id: payment.recharge_id,
        status: payment.status,
        amount: payment.amount&.to_s, # Convert BigDecimal to string for JSON
        currency: payment.currency,
        processed_at: payment.processed_at&.iso8601,
        charge_type: payment.charge_type,
        customer_email: payment.customer_email,
        customer_name: payment.customer_name,
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

      # Export sheet_entry relationship by identifier
      if payment.sheet_entry
        payment_data[:sheet_entry_email] = payment.sheet_entry.email
        payment_data[:sheet_entry_name] = payment.sheet_entry.name
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
              disposition: "attachment; filename=recharge_payments_backup_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
  end

  def import
    if params[:file].blank?
      redirect_to recharge_payments_path, alert: 'No file provided.'
      return
    end

    begin
      json_data = JSON.parse(params[:file].read)
      
      unless json_data.is_a?(Hash) && json_data['payments'].is_a?(Array)
        redirect_to recharge_payments_path, alert: 'Invalid JSON format. Expected object with "payments" array.'
        return
      end

      imported_count = 0
      updated_count = 0
      skipped_count = 0
      errors = []

      ActiveRecord::Base.transaction do
        json_data['payments'].each do |payment_data|
          begin
            # Find or initialize payment by recharge_id
            payment = RechargePayment.find_or_initialize_by(recharge_id: payment_data['recharge_id'])

            # Update all attributes
            payment.status = payment_data['status']
            
            # Handle amount conversion (can be string or number)
            if payment_data['amount'].present?
              payment.amount = BigDecimal(payment_data['amount'].to_s)
            end
            
            payment.currency = payment_data['currency']
            
            # Parse timestamps
            if payment_data['processed_at'].present?
              payment.processed_at = Time.parse(payment_data['processed_at'])
            end
            
            payment.charge_type = payment_data['charge_type']
            payment.customer_email = payment_data['customer_email']
            payment.customer_name = payment_data['customer_name']
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

            # Restore sheet_entry relationship
            if payment_data['sheet_entry_email'].present? || payment_data['sheet_entry_name'].present?
              sheet_entry = nil
              
              # Try to find by email first
              if payment_data['sheet_entry_email'].present?
                sheet_entry = SheetEntry.find_by('LOWER(email) = ?', payment_data['sheet_entry_email'].to_s.strip.downcase)
              end
              
              # Try to find by name if not found by email
              if sheet_entry.nil? && payment_data['sheet_entry_name'].present?
                sheet_entry = SheetEntry.find_by(name: payment_data['sheet_entry_name'])
              end
              
              # Try to find by email AND name combination
              if sheet_entry.nil? && payment_data['sheet_entry_email'].present? && payment_data['sheet_entry_name'].present?
                sheet_entry = SheetEntry.where('LOWER(email) = ? AND name = ?', 
                  payment_data['sheet_entry_email'].to_s.strip.downcase,
                  payment_data['sheet_entry_name']).first
              end
              
              payment.sheet_entry = sheet_entry if sheet_entry
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
            errors << "Payment #{payment_data['recharge_id']}: #{e.message}"
            Rails.logger.error("Failed to import Recharge payment #{payment_data['recharge_id']}: #{e.message}")
          end
        end
      end

      # Record CSV import in processor
      processor = PaymentProcessor.for('recharge')
      processor.record_csv_import!

      notice_parts = ["Import complete: #{imported_count} imported, #{updated_count} updated"]
      notice_parts << "#{skipped_count} skipped" if skipped_count > 0
      notice = notice_parts.join(', ')
      
      if errors.any?
        notice += ". Errors: #{errors.first(5).join('; ')}"
        notice += " (#{errors.count - 5} more)" if errors.count > 5
      end

      redirect_to recharge_payments_path, notice: notice
    rescue JSON::ParserError => e
      redirect_to recharge_payments_path, alert: "Invalid JSON: #{e.message}"
    rescue => e
      redirect_to recharge_payments_path, alert: "Import failed: #{e.message}"
    end
  end

  private

  def extract_customer_id(payment)
    return nil if payment.raw_attributes.blank?

    payment.raw_attributes.dig('customer', 'id') ||
      payment.raw_attributes['customer_id']
  end
end
