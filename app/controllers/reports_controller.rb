class ReportsController < AdminController
  LIMIT = 20

  def index
    @membership_status_unknown = User.where(membership_status: 'unknown', active: true).ordered_by_display_name.limit(LIMIT)
    @membership_status_unknown_count = User.where(membership_status: 'unknown', active: true).count
    @payment_type_unknown = User.where(payment_type: 'unknown', active: true).ordered_by_display_name.limit(LIMIT)
    @payment_type_unknown_count = User.where(payment_type: 'unknown', active: true).count
    @dues_status_unknown = User.where(dues_status: 'unknown', active: true).ordered_by_display_name.limit(LIMIT)
    @dues_status_unknown_count = User.where(dues_status: 'unknown', active: true).count
    @dues_status_lapsed = User.where(dues_status: 'lapsed', active: true).ordered_by_display_name.limit(LIMIT)
    @dues_status_lapsed_count = User.where(dues_status: 'lapsed', active: true).count
    
    # Find unmatched PayPal payments
    all_unmatched_paypal = []
    PaypalPayment.where.not(payer_id: nil).find_each do |payment|
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
    @unmatched_paypal_payments = all_unmatched_paypal.first(LIMIT)
    
    # Find unmatched Recharge payments
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
    @unmatched_recharge_payments = all_unmatched_recharge.first(LIMIT)
    
    @all_users = User.ordered_by_display_name
  end

  def view_all
    @report_type = params[:report_type]
    
    case @report_type
    when 'membership-status-unknown'
      @users = User.where(membership_status: 'unknown', active: true).ordered_by_display_name
      @title = 'Membership Status: Unknown'
    when 'payment-type-unknown'
      @users = User.where(payment_type: 'unknown', active: true).ordered_by_display_name
      @title = 'Payment Type: Unknown'
    when 'dues-status-unknown'
      @users = User.where(dues_status: 'unknown', active: true).ordered_by_display_name
      @title = 'Dues Status: Unknown'
    when 'dues-status-lapsed'
      @users = User.where(dues_status: 'lapsed', active: true).ordered_by_display_name
      @title = 'Dues Status: Lapsed'
    when 'unmatched-paypal'
      @unmatched_paypal_payments = []
      PaypalPayment.where.not(payer_id: nil).find_each do |payment|
        matching_user = User.where(paypal_account_id: payment.payer_id).first
        unless matching_user
          @unmatched_paypal_payments << {
            payment: payment,
            email: payment.payer_email,
            name: payment.payer_name
          }
        end
      end
      @title = 'Unmatched PayPal Payments'
    when 'unmatched-recharge'
      @unmatched_recharge_payments = []
      RechargePayment.find_each do |payment|
        customer_id = extract_customer_id(payment)
        next if customer_id.blank?
        
        matching_user = User.where(recharge_customer_id: customer_id.to_s).first
        unless matching_user
          @unmatched_recharge_payments << {
            payment: payment,
            email: payment.customer_email,
            name: payment.customer_name,
            customer_id: customer_id
          }
        end
      end
      @title = 'Unmatched Recharge Payments'
    else
      redirect_to reports_path, alert: 'Invalid report type.'
      return
    end
    
    @all_users = User.ordered_by_display_name
  end

  def update_user
    user = User.find(params[:user_id])
    action_type = params[:action_type]
    anchor = params[:anchor] || params[:tab] || 'membership-status-unknown'

    case action_type
    when 'activate'
      user.update!(active: true)
      notice = "#{user.display_name} activated."
    when 'deactivate'
      user.update!(active: false)
      notice = "#{user.display_name} deactivated."
    when 'ban'
      user.update!(membership_status: 'banned', active: false)
      notice = "#{user.display_name} banned."
    when 'deceased'
      user.update!(membership_status: 'deceased', active: false, payment_type: 'inactive')
      notice = "#{user.display_name} marked as deceased."
    when 'basic'
      user.update!(membership_status: 'basic')
      notice = "#{user.display_name} membership status set to basic."
    when 'coworking'
      user.update!(membership_status: 'coworking')
      notice = "#{user.display_name} membership status set to coworking."
    when 'sponsored'
      if anchor == 'payment-type-unknown'
        user.update!(payment_type: 'sponsored')
        notice = "#{user.display_name} payment type set to sponsored."
      else
        user.update!(membership_status: 'sponsored')
        notice = "#{user.display_name} membership status set to sponsored."
      end
    when 'guest'
      if anchor == 'payment-type-unknown'
        user.update!(payment_type: 'guest')
        notice = "#{user.display_name} payment type set to guest."
      else
        user.update!(membership_status: 'guest')
        notice = "#{user.display_name} membership status set to guest."
      end
    when 'cash'
      user.update!(payment_type: 'cash')
      notice = "#{user.display_name} payment type set to cash."
    when 'paypal'
      user.update!(payment_type: 'paypal')
      notice = "#{user.display_name} payment type set to PayPal."
    when 'recharge'
      user.update!(payment_type: 'recharge')
      notice = "#{user.display_name} payment type set to Recharge."
    when 'payment_guest'
      user.update!(payment_type: 'guest')
      notice = "#{user.display_name} payment type set to guest."
    when 'payment_sponsored'
      user.update!(payment_type: 'sponsored')
      notice = "#{user.display_name} payment type set to sponsored."
    else
      redirect_to reports_path, alert: 'Invalid action.'
      return
    end

    if params[:from_view_all] == 'true'
      redirect_to reports_view_all_path(anchor), notice: notice
    else
      redirect_to reports_path(tab: anchor), notice: notice
    end
  end
  
  private
  
  def extract_customer_id(payment)
    return nil if payment.raw_attributes.blank?
    
    payment.raw_attributes.dig('customer', 'id') ||
      payment.raw_attributes['customer_id']
  end
end
