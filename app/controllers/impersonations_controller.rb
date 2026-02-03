class ImpersonationsController < ApplicationController
  before_action :require_authenticated_user!
  before_action :require_true_admin!

  # POST /impersonate/:user_id
  def create
    user = User.find_by_param(params[:user_id])

    if user.nil?
      redirect_back fallback_location: users_path, alert: 'User not found.'
      return
    end

    if user == true_user
      redirect_back fallback_location: users_path, alert: 'You cannot impersonate yourself.'
      return
    end

    # Store the impersonated user ID
    session[:impersonated_user_id] = user.id

    # Log the impersonation
    Journal.create!(
      user: user,
      actor_user: true_user,
      action: 'impersonated',
      changes_json: {
        'impersonated_by' => { 'from' => nil, 'to' => true_user.display_name }
      },
      changed_at: Time.current
    )

    redirect_to user_path(user), notice: "You are now viewing as #{user.display_name}."
  end

  # DELETE /impersonate
  def destroy
    impersonated_user = User.find_by(id: session[:impersonated_user_id])

    # Log the end of impersonation
    if impersonated_user
      Journal.create!(
        user: impersonated_user,
        actor_user: true_user,
        action: 'impersonation_ended',
        changes_json: {
          'impersonation_ended_by' => { 'from' => nil, 'to' => true_user.display_name }
        },
        changed_at: Time.current
      )
    end

    session.delete(:impersonated_user_id)

    redirect_to users_path, notice: 'Impersonation ended. You are now viewing as yourself.'
  end

  private

  def require_true_admin!
    # Must be a real admin (not impersonating into admin)
    unless true_user&.is_admin?
      redirect_to root_path, alert: 'Only administrators can impersonate users.'
    end
  end
end
