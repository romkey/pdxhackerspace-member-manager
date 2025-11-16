class SheetEntriesController < AuthenticatedController
  def index
    @sheet_entries = SheetEntry.order(Arel.sql("LOWER(name) ASC"))
    @entry_count = @sheet_entries.count
    @with_email_count = SheetEntry.with_email.count
    @paying_count = SheetEntry.where("LOWER(status) = ?", "paying").count
    @sponsored_count = SheetEntry.where("LOWER(status) = ?", "sponsored").count
    @inactive_count = SheetEntry.where("status IS NULL OR status = ''").count

    user_emails = User.where.not(email: nil).pluck(Arel.sql("LOWER(email)"))
    @shared_email_count = if user_emails.any?
                            SheetEntry.where(email: user_emails).count
                          else
                            0
                          end

    user_names = User.where.not(full_name: nil).pluck(Arel.sql("LOWER(full_name)"))
    @shared_name_count = if user_names.any?
                           SheetEntry.where("LOWER(name) IN (?)", user_names).count
                         else
                           0
                         end
  end

  def show
    @sheet_entry = SheetEntry.find(params[:id])
    @payments = PaymentHistory.for_sheet_entry(@sheet_entry)
  end

  def sync
    GoogleSheets::SyncJob.perform_later
    redirect_to sheet_entries_path, notice: "Google Sheet sync scheduled."
  end
end

