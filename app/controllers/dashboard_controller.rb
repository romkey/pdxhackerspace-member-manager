class DashboardController < AdminController
  def index
    @user_count = User.count
    @active_user_count = User.active.count
    @last_synced_at = User.maximum(:last_synced_at)
    @sheet_entry_count = SheetEntry.count
    @slack_user_count = SlackUser.count
    @paypal_payment_count = PaypalPayment.count
    @recharge_payment_count = RechargePayment.count
    @users_for_search = User.ordered_by_display_name

    # Highlighted journal entries from the last 2 weeks
    @recent_highlights = Journal.highlighted
                                .includes(:user, :actor_user)
                                .where('changed_at >= ?', 2.weeks.ago)
                                .order(changed_at: :desc)
                                .limit(50)
  end
end
