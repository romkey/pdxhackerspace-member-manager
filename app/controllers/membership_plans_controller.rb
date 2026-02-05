class MembershipPlansController < AdminController
  skip_before_action :require_admin!, only: [:show]
  before_action :set_membership_plan, only: [:show, :edit, :update, :destroy]

  def index
    @membership_plans = MembershipPlan.ordered.includes(:users)
    @membership_plan = MembershipPlan.new
  end

  def show
    @other_plans = MembershipPlan.where.not(id: @membership_plan.id).ordered
  end

  def create
    @membership_plan = MembershipPlan.new(membership_plan_params)
    @membership_plans = MembershipPlan.ordered

    if @membership_plan.save
      redirect_to membership_plans_path, notice: 'Membership plan created successfully.'
    else
      render :index, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @membership_plan.update(membership_plan_params)
      redirect_to membership_plans_path, notice: 'Membership plan updated successfully.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    has_users = @membership_plan.primary? ? @membership_plan.users.any? : @membership_plan.supplementary_users.any?
    if has_users
      redirect_to membership_plans_path,
                  alert: 'Cannot delete membership plan that has users assigned to it.'
    else
      @membership_plan.destroy
      redirect_to membership_plans_path, notice: 'Membership plan deleted successfully.'
    end
  end

  private

  def set_membership_plan
    @membership_plan = MembershipPlan.find(params[:id])
  end

  def membership_plan_params
    params.require(:membership_plan).permit(:name, :cost, :billing_frequency, :description, :payment_link, :plan_type, :paypal_transaction_subject)
  end
end

