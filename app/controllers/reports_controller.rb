class ReportsController < AuthenticatedController
  def index
    @membership_status_unknown = User.where(membership_status: 'unknown', active: true).ordered_by_display_name
    @payment_type_unknown = User.where(payment_type: 'unknown', active: true).ordered_by_display_name
    @dues_status_unknown = User.where(dues_status: 'unknown', active: true).ordered_by_display_name
    @dues_status_lapsed = User.where(dues_status: 'lapsed', active: true).ordered_by_display_name
  end

  def update_user
    user = User.find(params[:user_id])
    action_type = params[:action_type]
    anchor = params[:anchor] || 'membership-status-unknown'

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

    redirect_to reports_path(anchor: anchor), notice: notice
  end
end
