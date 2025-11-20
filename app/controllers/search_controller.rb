class SearchController < AuthenticatedController
  def index
    @q = params[:q].to_s.strip
    return if @q.blank?

    pattern = "%#{@q.downcase}%"

    @users = User.where(
      "LOWER(COALESCE(full_name, '')) LIKE :p OR LOWER(COALESCE(email, '')) LIKE :p OR LOWER(authentik_id) LIKE :p", p: pattern
    ).order(:full_name).limit(25)
    @sheet_entries = SheetEntry.where("LOWER(COALESCE(name, '')) LIKE :p OR LOWER(COALESCE(email, '')) LIKE :p",
                                      p: pattern).order(:name).limit(25)
    @slack_users = SlackUser.where(
      "LOWER(COALESCE(display_name, '')) LIKE :p OR LOWER(COALESCE(real_name, '')) LIKE :p OR LOWER(COALESCE(username, '')) LIKE :p OR LOWER(COALESCE(email, '')) LIKE :p", p: pattern
    ).order(:display_name).limit(25)
    @paypal_payments = PaypalPayment.where(
      "LOWER(COALESCE(payer_email, '')) LIKE :p OR LOWER(COALESCE(payer_name, '')) LIKE :p OR LOWER(paypal_id) LIKE :p", p: pattern
    ).order(transaction_time: :desc).limit(25)
    @recharge_payments = RechargePayment.where(
      "LOWER(COALESCE(customer_email, '')) LIKE :p OR LOWER(COALESCE(customer_name, '')) LIKE :p OR LOWER(recharge_id) LIKE :p", p: pattern
    ).order(processed_at: :desc).limit(25)
  end
end
