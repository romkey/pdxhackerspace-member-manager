class DashboardController < AuthenticatedController
  def index
    @user_count = User.count
    @active_user_count = User.active.count
    @last_synced_at = User.maximum(:last_synced_at)
    @sheet_entry_count = SheetEntry.count
    @slack_user_count = SlackUser.count
    @paypal_payment_count = PaypalPayment.count
    @recharge_payment_count = RechargePayment.count
  end
end


