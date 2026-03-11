require 'prawn'
require 'rqrcode'

# Generates a receipt-sized PDF for 80mm thermal printers.
# 80mm ≈ 226.77pt. Printable area ~200pt with small margins.
# Variable length — Prawn will extend the page as needed.
class ParkingNoticeReceiptPdf
  PAPER_WIDTH_PT  = 226.77 # 80mm
  MARGIN          = 10
  CONTENT_WIDTH   = PAPER_WIDTH_PT - (MARGIN * 2)
  QR_SIZE         = 100

  # Generous initial height — Prawn auto-expands if content overflows a single page,
  # but for receipts we want one continuous page. We start tall and trim later.
  INITIAL_HEIGHT  = 2000

  def initialize(parking_notice, base_url: nil)
    @notice   = parking_notice
    @base_url = base_url || ENV.fetch('APP_BASE_URL', 'http://localhost:3000')
    @document = Prawn::Document.new(
      page_size: [PAPER_WIDTH_PT, INITIAL_HEIGHT],
      margin: [MARGIN, MARGIN, MARGIN, MARGIN]
    )
    generate
    trim_page
  end

  attr_reader :document

  def render
    document.render
  end

  private

  def generate
    header_block
    separator
    metadata_block
    separator
    description_block if @notice.description.present?
    location_block
    separator
    photos_block if @notice.photos.attached?
    separator
    qr_block
    separator
    footer_block
  end

  def header_block
    org = ENV.fetch('ORGANIZATION_NAME', 'Member Manager')

    document.font_size(8) { document.text org, align: :center, color: '000000' }
    document.move_down 4

    title = @notice.permit? ? 'PARKING PERMIT' : 'PARKING TICKET'
    document.font_size(18) { document.text title, align: :center, style: :bold }
    document.move_down 2

    document.font_size(10) do
      document.text "##{@notice.id}", align: :center, color: '444444'
    end
    document.move_down 2

    badge = @notice.active? ? '[ACTIVE]' : "[#{@notice.status.upcase}]"
    document.font_size(10) { document.text badge, align: :center, style: :bold }
    document.move_down 4
  end

  def metadata_block
    field('Issued', @notice.created_at.strftime('%b %d, %Y %l:%M %p'))
    field('Expires', @notice.expires_at.strftime('%b %d, %Y %l:%M %p'))
    field('Issued by', @notice.issued_by&.display_name || '—')

    if @notice.user.present?
      field('Member', @notice.user.display_name)
    end

    if @notice.cleared?
      field('Cleared by', @notice.cleared_by&.display_name || '—')
      field('Cleared on', @notice.cleared_at&.strftime('%b %d, %Y %l:%M %p') || '—')
    end
  end

  def description_block
    document.move_down 2
    document.font_size(8) { document.text 'DESCRIPTION', style: :bold, color: '444444' }
    document.move_down 2
    document.font_size(9) { document.text @notice.description, leading: 2 }
    document.move_down 4
  end

  def location_block
    return unless @notice.location.present? || @notice.location_detail.present?

    document.move_down 2
    document.font_size(8) { document.text 'LOCATION', style: :bold, color: '444444' }
    document.move_down 2
    document.font_size(9) { document.text @notice.location_display, leading: 2 }
    document.move_down 4
  end

  def photos_block
    document.move_down 2
    document.font_size(8) { document.text 'PHOTOS', style: :bold, color: '444444' }
    document.move_down 4

    photos = @notice.photos.select { |p| p.content_type.start_with?('image/') }
    photos.each do |photo|
      embed_photo(photo)
      document.move_down 6
    end
  end

  def embed_photo(photo)
    photo_data = photo.download
    tmpfile = Tempfile.new(['receipt_photo', File.extname(photo.filename.to_s)])
    tmpfile.binmode
    tmpfile.write(photo_data)
    tmpfile.rewind

    document.image tmpfile.path, fit: [CONTENT_WIDTH, 300], position: :center

    tmpfile.close
    tmpfile.unlink
  rescue StandardError => e
    Rails.logger.error("ParkingNoticeReceiptPdf: Failed to embed photo #{photo.filename}: #{e.message}")
    document.font_size(8) { document.text "(Photo: #{photo.filename})", color: '888888', align: :center }
  end

  def qr_block
    url = "#{@base_url}/parking_notices/#{@notice.id}"

    document.move_down 2
    x_offset = (CONTENT_WIDTH - QR_SIZE) / 2.0
    draw_qr_code(url, x_offset, document.cursor, QR_SIZE)
    document.move_down QR_SIZE + 4

    document.font_size(7) do
      document.text 'Scan to view details', align: :center, color: '444444'
    end
    document.move_down 4
  end

  def footer_block
    document.font_size(7) do
      document.text "Printed #{Time.current.strftime('%b %d, %Y %l:%M %p')}", align: :center, color: '888888'
    end
    document.move_down 6
  end

  def separator
    document.move_down 4
    document.dash(2, space: 2)
    document.stroke_horizontal_rule
    document.undash
    document.move_down 4
  end

  def field(label, value)
    document.font_size(8) do
      document.text "<b>#{label}:</b> #{value}", inline_format: true
    end
    document.move_down 2
  end

  def draw_qr_code(url, x_pos, y_pos, size)
    qr = RQRCode::QRCode.new(url)
    modules = qr.modules
    module_count = modules.size
    module_size = size.to_f / module_count

    modules.each_with_index do |row, row_idx|
      row.each_with_index do |dark, col_idx|
        next unless dark

        document.fill_color '000000'
        document.fill_rectangle(
          [x_pos + (col_idx * module_size), y_pos - (row_idx * module_size)],
          module_size,
          module_size
        )
      end
    end

    document.fill_color '000000'
  rescue StandardError => e
    Rails.logger.error("ParkingNoticeReceiptPdf: QR code failed for #{url}: #{e.message}")
  end

  # Shrink the page height to match actual content so the receipt isn't 2000pt tall.
  def trim_page
    used_height = INITIAL_HEIGHT - document.cursor + MARGIN
    document.page.dictionary.data[:MediaBox] = [0, 0, PAPER_WIDTH_PT, used_height]
    document.page.dictionary.data[:CropBox]  = [0, 0, PAPER_WIDTH_PT, used_height]
  end
end
