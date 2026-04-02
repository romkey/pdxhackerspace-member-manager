class MembershipPlansController < AdminController
  skip_before_action :require_admin!, only: [:show]
  before_action :set_membership_plan, only: %i[show edit update destroy]

  def index
    @membership_plans = MembershipPlan.shared.ordered.includes(:users)
    @personal_plans = MembershipPlan.personal.includes(:user).order(:name)
    @membership_plan = MembershipPlan.new
    @personal_plan = MembershipPlan.new
  end

  def show
    other_plans = MembershipPlan.shared.where.not(id: @membership_plan.id).ordered
    other_plans = other_plans.visible unless true_user_admin?
    @other_plans = other_plans
  end

  def edit; end

  def create
    @membership_plan = MembershipPlan.new(membership_plan_params)

    if @membership_plan.user_id.present?
      # Personal plan creation
      if @membership_plan.save
        redirect_to membership_plans_path(anchor: 'personal-plans'),
                    notice: "Personal plan created for #{@membership_plan.user.display_name}."
      else
        @membership_plans = MembershipPlan.shared.ordered.includes(:users)
        @personal_plans = MembershipPlan.personal.includes(:user).order(:name)
        @personal_plan = @membership_plan
        @membership_plan = MembershipPlan.new
        render :index, status: :unprocessable_content
      end
    elsif @membership_plan.save
      # Shared plan creation
      redirect_to membership_plans_path, notice: 'Membership plan created successfully.'
    else
      @membership_plans = MembershipPlan.shared.ordered.includes(:users)
      @personal_plans = MembershipPlan.personal.includes(:user).order(:name)
      @personal_plan = MembershipPlan.new
      render :index, status: :unprocessable_content
    end
  end

  def update
    if @membership_plan.update(membership_plan_params)
      redirect_to membership_plans_path, notice: 'Membership plan updated successfully.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @membership_plan.personal?
      if @membership_plan.cash_payments.any?
        redirect_to membership_plans_path(anchor: 'personal-plans'),
                    alert: 'Cannot delete personal plan that has cash payments recorded against it.'
      else
        @membership_plan.destroy
        redirect_to membership_plans_path(anchor: 'personal-plans'), notice: 'Personal plan deleted.'
      end
    else
      has_users = @membership_plan.primary? ? @membership_plan.users.any? : @membership_plan.supplementary_users.any?
      if has_users
        redirect_to membership_plans_path,
                    alert: 'Cannot delete membership plan that has members assigned to it.'
      else
        @membership_plan.destroy
        redirect_to membership_plans_path, notice: 'Membership plan deleted successfully.'
      end
    end
  end

  def manual_payments
    manual_plans = MembershipPlan.manual.ordered
    @members = []

    manual_plans.each do |plan|
      users = plan.primary? ? plan.users : plan.supplementary_users
      users.includes(:membership_plan).find_each do |user|
        next_date = user.next_payment_date
        @members << {
          user: user,
          plan: plan,
          next_payment_date: next_date,
          near_due: next_date.present? && next_date <= 7.days.from_now.to_date
        }
      end
    end

    # Sort: near-due first, then by next payment date (soonest first), then name
    @members.sort_by! do |m|
      [
        m[:near_due] ? 0 : 1,
        m[:next_payment_date] || Date.new(9999, 1, 1),
        m[:user].display_name.downcase
      ]
    end
  end

  def mark_dues_received
    user = User.find(params[:user_id])
    old_dues_status = user.dues_status
    dues_at = User.dues_due_at_from_payment_cycle(Date.current, user.membership_plan)
    user.update!(
      dues_status: 'current',
      last_payment_date: Date.current,
      membership_status: 'paying',
      dues_due_at: dues_at
    )
    Journal.create!(
      user: user,
      actor_user: current_user,
      action: 'membership_status_changed',
      changed_at: Time.current,
      changes_json: { 'dues_status' => { 'from' => old_dues_status, 'to' => 'current' },
                      'note' => 'Manual dues received' }
    )
    redirect_to manual_payments_membership_plans_path, notice: "Marked dues received for #{user.display_name}."
  end

  private

  def set_membership_plan
    @membership_plan = MembershipPlan.find(params[:id])
  end

  def membership_plan_params
    params.expect(membership_plan: %i[name cost billing_frequency description payment_link plan_type
                                      paypal_transaction_subject manual visible display_order user_id])
  end
end
