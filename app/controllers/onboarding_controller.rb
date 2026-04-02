class OnboardingController < AdminController
  before_action :set_user, only: %i[payment save_payment access save_rfid save_training
                                    mail approve_mail reject_mail approve_all_mail reject_all_mail]

  # Step 1: Member Info
  def member_info
    @user = User.new
  end

  def create_member
    @user = User.new(member_params)
    @user.membership_status = 'unknown'
    @user.dues_status = 'unknown'
    @user.active = false

    if @user.save
      redirect_to onboard_payment_path(@user), status: :see_other
    else
      render :member_info, status: :unprocessable_content
    end
  end

  # Step 2: Payment Info
  def payment; end

  def save_payment
    membership_type = params[:membership_type]

    case membership_type
    when 'paying'
      if params[:cash_plan] == '1'
        plan = MembershipPlan.create!(
          name: "Cash - #{@user.display_name}",
          cost: params[:plan_cost].to_f.positive? ? params[:plan_cost].to_f : 0,
          billing_frequency: params[:plan_billing_frequency] || 'monthly',
          description: params[:plan_notes].presence,
          plan_type: 'primary',
          manual: true,
          visible: false,
          user: @user
        )
        @user.update!(
          membership_status: 'paying',
          payment_type: 'cash',
          membership_plan: plan,
          active: true,
          dues_status: 'current'
        )
      else
        @user.update!(
          membership_status: 'paying',
          payment_type: 'unknown',
          active: true,
          dues_status: 'current'
        )
      end
    when 'sponsored'
      @user.update!(
        {
          membership_status: 'sponsored',
          payment_type: 'sponsored',
          active: true,
          dues_status: 'current'
        }.merge(onboarding_sponsored_guest_duration)
      )
    when 'guest'
      @user.update!(
        {
          membership_status: 'guest',
          payment_type: 'inactive',
          active: false,
          dues_status: 'unknown'
        }.merge(onboarding_sponsored_guest_duration)
      )
    end

    if membership_type == 'guest'
      redirect_to onboard_mail_path(@user), status: :see_other
    else
      redirect_to onboard_access_path(@user), status: :see_other
    end
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "Error: #{e.message}"
    render :payment, status: :unprocessable_content
  end

  # Step 3: Building Access
  def access
    @rfids = @user.rfids
    @building_access_topic = TrainingTopic.find_by('LOWER(name) LIKE ?', '%building access%')
    @has_building_access_training = @building_access_topic &&
                                    Training.exists?(trainee: @user, training_topic: @building_access_topic)
  end

  def save_rfid
    rfid_code = params[:rfid_code]&.strip
    if rfid_code.present?
      rfid = @user.rfids.build(rfid: rfid_code, notes: 'Added during onboarding')
      if rfid.save
        flash[:notice] = 'RFID key fob added.'
      else
        flash[:alert] = "Could not add RFID: #{rfid.errors.full_messages.join(', ')}"
      end
    else
      flash[:alert] = 'Please enter an RFID code.'
    end
    redirect_to onboard_access_path(@user), status: :see_other
  end

  def save_training
    topic = TrainingTopic.find_by('LOWER(name) LIKE ?', '%building access%')
    unless topic
      flash[:alert] = 'Building Access training topic not found. Please create it under Settings > Training Topics.'
      redirect_to onboard_mail_path(@user), status: :see_other
      return
    end

    unless Training.exists?(trainee: @user, training_topic: topic)
      training = Training.create!(
        trainee: @user,
        trainer: current_user,
        training_topic: topic,
        trained_at: Time.current
      )

      Journal.create!(
        user: @user,
        actor_user: current_user,
        action: 'training_added',
        changes_json: {
          'training' => {
            'topic' => topic.name,
            'trainer' => current_user.display_name,
            'trained_at' => training.trained_at.iso8601
          }
        },
        changed_at: Time.current,
        highlight: true
      )
    end

    flash[:notice] = 'Building Access training recorded.'
    redirect_to onboard_mail_path(@user), status: :see_other
  end

  # Step 4: Review Mail
  def mail
    @queued_mails = @user.queued_mails.includes(:email_template, :reviewed_by).newest_first
    @pending_count = @queued_mails.count(&:pending?)
  end

  def approve_mail
    qm = QueuedMail.find(params[:mail_id])
    qm.approve!(current_user) if qm.pending?
    redirect_to onboard_mail_path(@user), status: :see_other
  end

  def reject_mail
    qm = QueuedMail.find(params[:mail_id])
    qm.reject!(current_user) if qm.pending?
    redirect_to onboard_mail_path(@user), status: :see_other
  end

  def approve_all_mail
    @user.queued_mails.pending.find_each { |qm| qm.approve!(current_user) }
    redirect_to onboard_mail_path(@user), notice: 'All pending messages approved.', status: :see_other
  end

  def reject_all_mail
    @user.queued_mails.pending.find_each { |qm| qm.reject!(current_user) }
    redirect_to onboard_mail_path(@user), notice: 'All pending messages rejected.', status: :see_other
  end

  private

  def onboarding_sponsored_guest_duration
    m = params[:sponsored_guest_duration_months].to_s.strip.presence&.to_i
    return {} unless m.present? && m.positive?

    { dues_due_at: Time.current + m.months }
  end

  def set_user
    @user = User.find_by_param(params[:id])
  end

  def member_params
    params.expect(user: %i[full_name email username])
  end
end
