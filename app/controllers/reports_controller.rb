class ReportsController < AdminController
  include Pagy::Backend
  
  LIMIT = 20
  RECHARGE_PER_PAGE = 50

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
    
    # Find unmatched Recharge payments (ordered by most recent first)
    load_unmatched_recharge_payments
    
    @all_users = User.ordered_by_display_name
    
    # Prepare chart data
    prepare_chart_data
  end
  
  def prepare_chart_data
    # Active members per month
    # Count users who have activity (payments) in or before each month and are currently active
    @active_members_data = {}
    start_date = 12.months.ago.beginning_of_month
    end_date = Time.current.end_of_month
    
    # Get users with their earliest payment dates
    # Users with PayPal payments
    paypal_user_dates = PaypalPayment.joins(:user)
                                      .where(users: { active: true })
                                      .where.not(transaction_time: nil)
                                      .group('users.id')
                                      .minimum('paypal_payments.transaction_time')
    
    # Users with Recharge payments
    recharge_user_dates = RechargePayment.joins(:user)
                                         .where(users: { active: true })
                                         .where.not(processed_at: nil)
                                         .group('users.id')
                                         .minimum('recharge_payments.processed_at')
    
    # Combine to get earliest payment date per user
    user_earliest_payment = {}
    paypal_user_dates.each do |user_id, date|
      user_earliest_payment[user_id] = [user_earliest_payment[user_id], date].compact.min
    end
    recharge_user_dates.each do |user_id, date|
      user_earliest_payment[user_id] = [user_earliest_payment[user_id], date].compact.min
    end
    
    # Get all active users created dates
    active_user_created = User.where(active: true).pluck(:id, :created_at).to_h
    
    (start_date.to_date..end_date.to_date).select { |d| d.day == 1 }.each do |month_start|
      month_key = month_start.strftime('%Y-%m')
      month_end = month_start.end_of_month
      
      # Count users who:
      # 1. Are currently active, AND
      # 2. Have a payment on or before this month, OR
      # 3. Were created on or before this month (for users without payments yet)
      count = active_user_created.count do |user_id, created_at|
        earliest_payment = user_earliest_payment[user_id]
        (earliest_payment && earliest_payment <= month_end) || created_at <= month_end
      end
      
      @active_members_data[month_key] = count
    end
    
    # Revenue per month (PayPal and Recharge)
    @revenue_data = { paypal: {}, recharge: {} }
    
    # PayPal revenue by month
    PaypalPayment.where.not(transaction_time: nil)
                 .where.not(amount: nil)
                 .where('transaction_time >= ?', start_date)
                 .group_by { |p| p.transaction_time.beginning_of_month.strftime('%Y-%m') }
                 .each do |month, payments|
      @revenue_data[:paypal][month] = payments.sum(&:amount).to_f
    end
    
    # Recharge revenue by month
    RechargePayment.where.not(processed_at: nil)
                   .where.not(amount: nil)
                   .where('processed_at >= ?', start_date)
                   .group_by { |p| p.processed_at.beginning_of_month.strftime('%Y-%m') }
                   .each do |month, payments|
      @revenue_data[:recharge][month] = payments.sum(&:amount).to_f
    end
    
    # Ensure all months are represented in both datasets
    all_months = (@active_members_data.keys + @revenue_data[:paypal].keys + @revenue_data[:recharge].keys).uniq.sort
    all_months.each do |month|
      @active_members_data[month] ||= 0
      @revenue_data[:paypal][month] ||= 0
      @revenue_data[:recharge][month] ||= 0
    end
    
    # Convert to arrays for Chart.js
    @chart_months = all_months
    @active_members_counts = all_months.map { |m| @active_members_data[m] }
    @paypal_revenue = all_months.map { |m| @revenue_data[:paypal][m] }
    @recharge_revenue = all_months.map { |m| @revenue_data[:recharge][m] }
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
      payments = RechargePayment.unmatched.ordered
      @unmatched_recharge_payments = payments.map do |payment|
        {
          payment: payment,
          email: payment.customer_email,
          name: payment.customer_name,
          customer_id: payment.customer_id
        }
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
    when 'paying'
      user.update!(membership_status: 'paying')
      notice = "#{user.display_name} membership status set to paying."
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
  
  # Turbo frame action for paginating/reloading Recharge payments
  def unmatched_recharge
    load_unmatched_recharge_payments
    
    render partial: 'unmatched_recharge_content', locals: {
      payments: @unmatched_recharge_payments,
      pagy: @pagy_recharge,
      count: @unmatched_recharge_payments_count
    }
  end

  private

  def load_unmatched_recharge_payments
    # Get unmatched recharge payments using efficient SQL query, ordered by most recent first
    unmatched_query = RechargePayment.unmatched.ordered
    
    @unmatched_recharge_payments_count = unmatched_query.count
    @pagy_recharge, payments = pagy(unmatched_query, limit: RECHARGE_PER_PAGE, page_param: :recharge_page)
    
    # Transform to the expected format
    @unmatched_recharge_payments = payments.map do |payment|
      {
        payment: payment,
        email: payment.customer_email,
        name: payment.customer_name,
        customer_id: payment.customer_id
      }
    end
  end
end
