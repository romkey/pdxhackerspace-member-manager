class MailLogController < AdminController
  def index
    @log_entries = MailLogEntry.newest_first
                               .includes(queued_mail: :recipient, actor: [])
                               .limit(200)
  end
end
