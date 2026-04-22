class CashPaymentsController < AdminController
  include Pagy::Method

  before_action :set_cash_payment, only: %i[show edit update destroy]

  def index
    @cash_payments = CashPayment.includes(:user, :membership_plan, :recorded_by).ordered
    @pagy, @cash_payments = pagy(@cash_payments, limit: 25)
  end

  def show; end

  def new
    @cash_payment = CashPayment.new(paid_on: Date.current)
    @cash_payment.user_id = params[:user_id] if params[:user_id].present?

    return if @cash_payment.user_id.blank?

    user = User.find(@cash_payment.user_id)
    personal_plans = user.personal_membership_plans
    @cash_payment.membership_plan_id = personal_plans.first&.id if personal_plans.one?
  end

  def edit; end

  def create
    @cash_payment = CashPayment.new(cash_payment_params)
    @cash_payment.recorded_by = current_user

    if @cash_payment.save
      PaymentEvent.create!(
        user: @cash_payment.user,
        event_type: 'payment',
        source: 'cash',
        amount: @cash_payment.amount,
        currency: 'USD',
        occurred_at: @cash_payment.paid_on&.beginning_of_day || Time.current,
        external_id: "CASH-#{@cash_payment.id}",
        details: "Cash payment — #{@cash_payment.membership_plan&.name || 'Unknown plan'}",
        cash_payment: @cash_payment
      )
      update_user_dues_status(@cash_payment)
      redirect_to cash_payment_path(@cash_payment),
                  notice: "Cash payment recorded for #{@cash_payment.user.display_name}."
    else
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @cash_payment.update(cash_payment_params)
      redirect_to cash_payment_path(@cash_payment), notice: 'Cash payment updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    user_name = @cash_payment.user.display_name
    @cash_payment.destroy
    redirect_to cash_payments_path, notice: "Cash payment for #{user_name} deleted."
  end

  private

  def set_cash_payment
    @cash_payment = CashPayment.find(params[:id])
  end

  def cash_payment_params
    params.expect(cash_payment: %i[user_id membership_plan_id amount paid_on notes])
  end

  def update_user_dues_status(cash_payment)
    user = cash_payment.user
    old_dues_status = user.dues_status

    updates = user.apply_payment_updates(
      { time: cash_payment.paid_on.beginning_of_day, amount: cash_payment.amount },
      { payment_type: 'cash', last_payment_date: cash_payment.paid_on }
    )

    user.update!(updates) if updates.present?

    Journal.create!(
      user: user,
      actor_user: current_user,
      action: 'membership_status_changed',
      changed_at: Time.current,
      changes_json: {
        'dues_status' => { 'from' => old_dues_status, 'to' => 'current' },
        'note' => "Cash payment of $#{format('%.2f', cash_payment.amount)} recorded"
      }
    )
  end
end
