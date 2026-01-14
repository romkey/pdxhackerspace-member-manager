class EmailTemplatesController < AdminController
  before_action :set_email_template, only: [:show, :edit, :update, :preview, :toggle]

  def index
    @email_templates = EmailTemplate.ordered
  end

  def show; end

  def edit; end

  def update
    if @email_template.update(email_template_params)
      redirect_to email_templates_path, notice: "Email template '#{@email_template.name}' was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def preview
    @rendered = @email_template.preview
    render layout: false
  end

  def toggle
    @email_template.update!(enabled: !@email_template.enabled)
    status = @email_template.enabled? ? 'enabled' : 'disabled'
    redirect_to email_templates_path, notice: "Email template '#{@email_template.name}' has been #{status}."
  end

  def seed
    EmailTemplate.seed_defaults!
    redirect_to email_templates_path, notice: "Default email templates have been seeded."
  end

  def test_send
    @email_template = EmailTemplate.find(params[:id])
    
    # Find a user to send test to (prefer current user)
    test_user = current_user
    
    if test_user&.email.present?
      # Render the template
      variables = build_variables_for_user(test_user)
      rendered = @email_template.render(variables)
      
      # Send via ActionMailer
      TestMailer.send_template(
        to: test_user.email,
        subject: rendered[:subject],
        body_html: rendered[:body_html],
        body_text: rendered[:body_text]
      ).deliver_later
      
      redirect_to email_templates_path, notice: "Test email sent to #{test_user.email}."
    else
      redirect_to email_templates_path, alert: "Could not send test email - no email address available."
    end
  end

  private

  def set_email_template
    @email_template = EmailTemplate.find(params[:id])
  end

  def email_template_params
    params.require(:email_template).permit(:name, :description, :subject, :body_html, :body_text, :enabled)
  end

  def build_variables_for_user(user, extra = {})
    {
      member_name: user.display_name,
      member_email: user.email || 'Not provided',
      member_username: user.username || 'Not set',
      organization_name: ENV.fetch('ORGANIZATION_NAME', 'Member Manager'),
      date: Date.current.strftime('%B %d, %Y'),
      app_url: ENV.fetch('APP_BASE_URL', 'http://localhost:3000')
    }.merge(extra)
  end
end
