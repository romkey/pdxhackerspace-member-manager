# SPDX-FileCopyrightText: 2026 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

require 'prawn'
require 'prawn/table'
require 'rqrcode'
require 'stringio'
require 'tempfile'

class IncidentReportPdf
  include Prawn::View

  def initialize(incident_report)
    @incident_report = incident_report
    @document = Prawn::Document.new(
      page_size: 'LETTER',
      margin: [50, 50, 50, 50]
    )
    generate
  end

  def document
    @document
  end

  private

  def generate
    header
    move_down 20
    metadata_section
    move_down 20
    description_section
    move_down 20
    resolution_section if @incident_report.resolution.present?
    move_down 20
    photos_section if @incident_report.photos.attached?
    move_down 20
    links_section if @incident_report.links.any?
    footer
  end

  def header
    text 'INCIDENT REPORT', size: 24, style: :bold, align: :center
    move_down 10
    stroke_horizontal_rule
    move_down 10
    text @incident_report.subject, size: 16, style: :bold, align: :center
    move_down 5
    text "Report ##{@incident_report.id}", size: 10, color: '666666', align: :center
  end

  def metadata_section
    status_text = @incident_report.status_display
    status_color = case @incident_report.status
                   when 'draft' then '666666'
                   when 'in_progress' then 'CC8800'
                   when 'resolved' then '228822'
                   else '000000'
                   end

    data = [
      ['Date:', @incident_report.incident_date.strftime('%B %d, %Y')],
      ['Type:', @incident_report.incident_type_display],
      ['Status:', status_text],
      ['Reporter:', @incident_report.reporter&.display_name || 'Unknown']
    ]

    if @incident_report.involved_members.any?
      members_list = @incident_report.involved_members.map(&:display_name).join("\n")
      data << ['Involved Members:', members_list]
    else
      data << ['Involved Members:', 'None listed (may involve non-members)']
    end

    table(data, column_widths: [120, 392]) do |t|
      t.cells.borders = []
      t.cells.padding = [4, 8]
      t.column(0).font_style = :bold
      t.column(0).text_color = '444444'
    end
  end

  def description_section
    section_header('Description')
    move_down 8

    if @incident_report.description.present?
      text @incident_report.description, size: 11, leading: 4
    else
      text 'No description provided.', size: 11, color: '888888', style: :italic
    end
  end

  def resolution_section
    section_header('Resolution')
    move_down 8

    bounding_box([0, cursor], width: bounds.width) do
      fill_color 'E8F5E9'
      fill_rectangle([0, cursor], bounds.width, height_of(@incident_report.resolution, size: 11) + 20)
      fill_color '000000'
      move_down 10
      indent(10) do
        text @incident_report.resolution, size: 11, leading: 4
      end
    end
    move_down 10
  end

  def photos_section
    section_header('Photos')
    move_down 8

    # Calculate image dimensions - fit 2 per row with some spacing
    max_width = (bounds.width - 20) / 2
    max_height = 200

    photos = @incident_report.photos.select { |p| p.content_type.start_with?('image/') }

    photos.each_slice(2) do |photo_pair|
      row_height = 0

      photo_pair.each_with_index do |photo, index|
        x_position = index * (max_width + 20)

        begin
          # Download the photo data
          photo_data = photo.download

          # Create a temporary file for the image
          tempfile = Tempfile.new(['photo', File.extname(photo.filename.to_s)])
          tempfile.binmode
          tempfile.write(photo_data)
          tempfile.rewind

          # Calculate dimensions to fit within max bounds while preserving aspect ratio
          img = image tempfile.path, at: [x_position, cursor], fit: [max_width, max_height]

          # Track the tallest image in this row
          row_height = [row_height, img.scaled_height].max

          tempfile.close
          tempfile.unlink
        rescue StandardError => e
          Rails.logger.error("Failed to embed photo #{photo.filename}: #{e.message}")
          # Show placeholder text for failed images
          text_box "Photo: #{photo.filename}", at: [x_position, cursor], width: max_width, size: 9, color: '888888'
          row_height = [row_height, 20].max
        end
      end

      move_down row_height + 15
    end
  end

  def links_section
    section_header('Related Links')
    move_down 8

    qr_size = 60

    @incident_report.links.ordered.each do |link|
      start_y = cursor

      # Draw QR code directly using Prawn rectangles
      draw_qr_code(link.url, 0, cursor, qr_size)

      # Draw text to the right of QR code
      bounding_box([qr_size + 15, start_y], width: bounds.width - qr_size - 15) do
        text link.title, size: 11, style: :bold
        move_down 3
        text link.url, size: 9, color: '0066CC'
      end

      # Move cursor below the QR code
      move_cursor_to [start_y - qr_size - 12, cursor].min

      move_down 8
    end
  end

  def draw_qr_code(url, x, y, size)
    qr = RQRCode::QRCode.new(url)
    modules = qr.modules
    module_count = modules.size
    module_size = size.to_f / module_count

    modules.each_with_index do |row, row_idx|
      row.each_with_index do |dark, col_idx|
        if dark
          # Draw a filled rectangle for dark modules
          fill_color '000000'
          fill_rectangle(
            [x + (col_idx * module_size), y - (row_idx * module_size)],
            module_size,
            module_size
          )
        end
      end
    end

    # Reset fill color
    fill_color '000000'
  rescue StandardError => e
    Rails.logger.error("Failed to draw QR code for #{url}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
  end

  def section_header(title)
    text title, size: 14, style: :bold
    stroke_horizontal_rule
  end

  def footer
    repeat(:all) do
      bounding_box([0, 30], width: bounds.width, height: 30) do
        stroke_horizontal_rule
        move_down 5
        font_size 8 do
          text_box "Generated: #{Time.current.strftime('%B %d, %Y at %I:%M %p')}",
                   at: [0, cursor],
                   width: bounds.width / 2,
                   align: :left,
                   color: '888888'
          text_box "Incident Report ##{@incident_report.id}",
                   at: [bounds.width / 2, cursor],
                   width: bounds.width / 2,
                   align: :right,
                   color: '888888'
        end
      end
    end
  end
end
