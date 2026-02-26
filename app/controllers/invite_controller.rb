class InviteController < ApplicationController
  before_action :find_invitation
  before_action :check_invitation_valid, only: [:show, :accept]

  def show
    return if performed?
    @user = User.new
  end

  def accept
    return if performed?

    @user = User.new(user_params)
    @user.email = @invitation.email
    @user.active = true
    @user.membership_status = 'unknown'
    @user.dues_status = 'unknown'

    if @user.save
      @invitation.accept!(@user)

      Journal.create!(
        user: @user,
        actor_user: @invitation.invited_by,
        action: 'invitation_accepted',
        changes_json: {
          'invitation' => {
            'type' => @invitation.type_label,
            'invited_by' => @invitation.invited_by.display_name,
            'accepted_at' => Time.current.iso8601
          }
        },
        changed_at: Time.current,
        highlight: true
      )

      session[:user_id] = @user.id
      redirect_to profile_setup_path, notice: "Welcome to #{ENV.fetch('ORGANIZATION_NAME', 'Member Manager')}! Let's set up your profile."
    else
      render :show, status: :unprocessable_entity
    end
  end

  def accepted
    if @invitation.nil?
      @error = :not_found
      render :show
      return
    end

    unless @invitation.accepted?
      redirect_to invite_path(@invitation.token)
      return
    end

    @user = @invitation.user
  end

  private

  def find_invitation
    @invitation = Invitation.find_by(token: params[:token])
  end

  def check_invitation_valid
    if @invitation.nil?
      @error = :not_found
    elsif @invitation.accepted?
      @error = :already_accepted
    elsif @invitation.cancelled?
      @error = :cancelled
    elsif @invitation.expired?
      @error = :expired
    end

    render :show if @error && !performed?
  end

  def user_params
    params.require(:user).permit(:full_name, :username)
  end
end
