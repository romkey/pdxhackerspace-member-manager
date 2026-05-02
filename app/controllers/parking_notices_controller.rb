class ParkingNoticesController < AdminController
  include Pagy::Method

  before_action :set_parking_notice,
                only: %i[show edit update clear download_pdf print_notice remove_photo download_photo]

  def index
    @parking_notices = ParkingNotice.includes(:user, :issued_by).newest_first

    @parking_notices = @parking_notices.where(notice_type: params[:type]) if params[:type].present?
    @parking_notices = @parking_notices.where(status: params[:status]) if params[:status].present?

    @status_counts = {
      all: ParkingNotice.count,
      active: ParkingNotice.active_notices.count,
      expired: ParkingNotice.expired_notices.count,
      cleared: ParkingNotice.cleared_notices.count
    }

    @pagy, @parking_notices = pagy(@parking_notices, limit: 25)
  end

  def show
    @printers = Printer.ordered
  end

  def new
    @parking_notice = ParkingNotice.new(
      notice_type: params[:type].presence || 'permit',
      expires_at: 7.days.from_now
    )
    load_form_data
  end

  def edit
    load_form_data
  end

  def create
    @parking_notice = ParkingNotice.new(parking_notice_params)
    @parking_notice.issued_by = current_user

    if @parking_notice.save
      template_key = @parking_notice.permit? ? 'parking_permit_issued' : 'parking_ticket_issued'
      journal_action = @parking_notice.permit? ? 'parking_permit_issued' : 'parking_ticket_issued'

      @parking_notice.record_journal_entry!(journal_action, actor: current_user)
      @parking_notice.enqueue_notification!(template_key)

      redirect_to parking_notice_path(@parking_notice),
                  notice: "Parking #{@parking_notice.notice_type} created successfully."
    else
      load_form_data
      render :new, status: :unprocessable_content
    end
  end

  def update
    if @parking_notice.update(parking_notice_params)
      redirect_to parking_notice_path(@parking_notice),
                  notice: "Parking #{@parking_notice.notice_type} updated successfully."
    else
      load_form_data
      render :edit, status: :unprocessable_content
    end
  end

  def clear
    @parking_notice.clear!(current_user)
    @parking_notice.record_journal_entry!('parking_notice_cleared', actor: current_user)

    redirect_to parking_notice_path(@parking_notice),
                notice: "Parking #{@parking_notice.notice_type} marked as cleared."
  end

  def download_pdf
    pdf = ParkingNoticePdf.new(@parking_notice)
    type_label = @parking_notice.permit? ? 'permit' : 'ticket'
    filename = "parking_#{type_label}_#{@parking_notice.id}_#{@parking_notice.created_at.strftime('%Y%m%d')}.pdf"

    send_data pdf.render,
              filename: filename,
              type: 'application/pdf',
              disposition: 'attachment'
  end

  def print_notice
    printer = Printer.find(params[:printer_id])
    cookies[:last_printer_id] = { value: printer.id.to_s, expires: 1.year.from_now }

    pdf, cups_options = parking_notice_pdf_and_cups_options(printer)

    job_id = CupsService.print_data(
      pdf.render,
      printer.cups_printer_name,
      cups_printer_server: printer.cups_printer_server,
      filename: "parking_notice_#{@parking_notice.id}.pdf",
      options: cups_options
    )

    redirect_to parking_notice_path(@parking_notice),
                notice: "Printed to #{printer.name} (job #{job_id})."
  rescue CupsService::PrintError => e
    redirect_to parking_notice_path(@parking_notice),
                alert: "Print failed: #{e.message}"
  end

  def remove_photo
    photo = @parking_notice.photos.find(params[:photo_id])
    photo.purge
    redirect_to parking_notice_path(@parking_notice), notice: 'Photo removed.'
  end

  def download_photo
    photo = @parking_notice.photos.find(params[:photo_id])
    disposition = params[:disposition] == 'inline' ? 'inline' : 'attachment'

    send_data photo.download,
              filename: photo.filename.to_s,
              type: photo.content_type,
              disposition: disposition
  end

  private

  def parking_notice_pdf_and_cups_options(printer)
    force_letter = params[:layout].to_s.in?(%w[letter full_page])
    if !force_letter && printer.thermal_receipt_printer?
      pdf = ParkingNoticeReceiptPdf.new(
        @parking_notice,
        layout: :thermal,
        thermal_width_mm: printer.thermal_roll_width_mm
      )
      [pdf, CupsService::THERMAL_PDF_OPTIONS]
    else
      [ParkingNoticeReceiptPdf.new(@parking_notice, layout: :full_page), {}]
    end
  end

  def set_parking_notice
    @parking_notice = ParkingNotice.find(params[:id])
  end

  def load_form_data
    @rooms = Room.ordered
    @users = User.ordered_by_display_name
  end

  def parking_notice_params
    params.expect(
      parking_notice: [:notice_type, :user_id, :description, :location,
                       :location_detail, :expires_at, :notes, { photos: [] }]
    )
  end
end
