class QueuedMailsController < AdminController
  before_action :set_queued_mail, only: [:show, :edit, :update, :approve, :reject, :regenerate]

  def index
    @filter = params[:filter].presence || 'pending'
    @queued_mails = case @filter
                    when 'approved' then QueuedMail.approved
                    when 'rejected' then QueuedMail.rejected
                    when 'all'      then QueuedMail.all
                    else QueuedMail.pending
                    end
    @queued_mails = @queued_mails.newest_first.includes(:recipient, :email_template, :reviewed_by)
    @pending_count = QueuedMail.pending.count
  end

  def show; end

  def edit
    redirect_to queued_mail_path(@queued_mail), alert: 'Only pending messages can be edited.' unless @queued_mail.pending?
  end

  def update
    unless @queued_mail.pending?
      redirect_to queued_mail_path(@queued_mail), alert: 'Only pending messages can be edited.'
      return
    end

    if @queued_mail.update(queued_mail_params)
      @queued_mail.log_edit!(current_user)
      redirect_to queued_mail_path(@queued_mail), notice: 'Message updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def approve
    unless @queued_mail.pending?
      redirect_to queued_mail_path(@queued_mail), alert: 'This message has already been reviewed.'
      return
    end

    unless helpers.smtp_configured?
      redirect_to queued_mail_path(@queued_mail), alert: 'Cannot send email: SMTP is not configured.'
      return
    end

    @queued_mail.approve!(current_user)
    redirect_to queued_mails_path, notice: "Message to #{@queued_mail.to} has been approved and sent."
  end

  def reject
    unless @queued_mail.pending?
      redirect_to queued_mail_path(@queued_mail), alert: 'This message has already been reviewed.'
      return
    end

    @queued_mail.reject!(current_user)
    redirect_to queued_mails_path, notice: "Message to #{@queued_mail.to} has been rejected."
  end

  def regenerate
    unless @queued_mail.pending?
      redirect_to queued_mail_path(@queued_mail), alert: 'Only pending messages can be regenerated.'
      return
    end

    unless @queued_mail.can_regenerate?
      redirect_to queued_mail_path(@queued_mail), alert: 'This message cannot be regenerated (no template or recipient).'
      return
    end

    @queued_mail.regenerate!(actor: current_user)
    redirect_to queued_mail_path(@queued_mail), notice: 'Message regenerated from template.'
  end

  private

  def set_queued_mail
    @queued_mail = QueuedMail.find(params[:id])
  end

  def queued_mail_params
    params.require(:queued_mail).permit(:to, :subject, :body_html, :body_text)
  end
end
