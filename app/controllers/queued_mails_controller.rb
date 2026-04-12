class QueuedMailsController < AdminController
  before_action :set_queued_mail, only: %i[show edit update approve reject regenerate retry_delivery rewrite_with_ai]

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
    return if @queued_mail.pending?

    redirect_to queued_mail_path(@queued_mail),
                alert: 'Only pending messages can be edited.'
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
      render :edit, status: :unprocessable_content
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

  def retry_delivery
    unless @queued_mail.delivery_failed?
      redirect_to queued_mail_path(@queued_mail), alert: 'Only failed messages can be retried.'
      return
    end

    unless helpers.smtp_configured?
      redirect_to queued_mail_path(@queued_mail), alert: 'Cannot send email: SMTP is not configured.'
      return
    end

    @queued_mail.retry_delivery!
    redirect_to queued_mail_path(@queued_mail), notice: "Retrying delivery to #{@queued_mail.to}..."
  end

  def approve_all
    unless helpers.smtp_configured?
      redirect_to queued_mails_path, alert: 'Cannot send email: SMTP is not configured.'
      return
    end

    pending = QueuedMail.pending
    count = pending.count
    pending.find_each { |qm| qm.approve!(current_user) }
    redirect_to queued_mails_path, notice: "Approved and sent #{count} message#{'s' if count != 1}."
  end

  def reject_all
    pending = QueuedMail.pending
    count = pending.count
    pending.find_each { |qm| qm.reject!(current_user) }
    redirect_to queued_mails_path, notice: "Rejected #{count} message#{'s' if count != 1}."
  end

  def regenerate
    unless @queued_mail.pending?
      redirect_to queued_mail_path(@queued_mail), alert: 'Only pending messages can be regenerated.'
      return
    end

    unless @queued_mail.can_regenerate?
      redirect_to queued_mail_path(@queued_mail),
                  alert: 'This message cannot be regenerated (no template or recipient).'
      return
    end

    @queued_mail.regenerate!(actor: current_user)
    redirect_to queued_mail_path(@queued_mail), notice: 'Message regenerated from template.'
  end

  def rewrite_with_ai
    unless @queued_mail.pending?
      render json: { error: 'Only pending messages can be rewritten.' }, status: :unprocessable_content
      return
    end

    attrs = rewrite_params
    result = QueuedMails::RewriteWithAi.call(
      queued_mail: @queued_mail,
      subject: attrs[:subject],
      body_html: attrs[:body_html],
      body_text: attrs[:body_text]
    )

    if result.success?
      render json: {
        body_html: result.body_html,
        body_text: result.body_text,
        message: result.message
      }
    else
      render json: { error: result.message }, status: :unprocessable_content
    end
  end

  private

  def set_queued_mail
    @queued_mail = QueuedMail.find(params[:id])
  end

  def queued_mail_params
    params.expect(queued_mail: %i[to subject body_html body_text])
  end

  def rewrite_params
    params.expect(rewrite: %i[subject body_html body_text])
  end
end
