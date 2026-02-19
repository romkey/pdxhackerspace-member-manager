class CashPaymentsController < AdminController
  include Pagy::Backend

  before_action :set_cash_payment, only: [:show, :edit, :update, :destroy]

  def index
    @cash_payments = CashPayment.includes(:user, :membership_plan, :recorded_by).ordered
    @pagy, @cash_payments = pagy(@cash_payments, limit: 25)
  end

  def show
  end

  def new
    @cash_payment = CashPayment.new(paid_on: Date.current)
    @cash_payment.user_id = params[:user_id] if params[:user_id].present?

    if @cash_payment.user_id.present?
      user = User.find(@cash_payment.user_id)
      personal_plans = user.personal_membership_plans
      @cash_payment.membership_plan_id = personal_plans.first&.id if personal_plans.one?
    end
  end

  def create
    @cash_payment = CashPayment.new(cash_payment_params)
    @cash_payment.recorded_by = current_user

    if @cash_payment.save
      update_user_dues_status(@cash_payment)
      redirect_to cash_payment_path(@cash_payment), notice: "Cash payment recorded for #{@cash_payment.user.display_name}."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
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
    params.require(:cash_payment).permit(:user_id, :membership_plan_id, :amount, :paid_on, :notes)
  end

  def update_user_dues_status(cash_payment)
    user = cash_payment.user
    old_dues_status = user.dues_status
    user.update!(
      dues_status: 'current',
      last_payment_date: cash_payment.paid_on,
      membership_status: 'paying',
      payment_type: 'cash'
    )
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
