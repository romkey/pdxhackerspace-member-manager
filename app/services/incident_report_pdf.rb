# SPDX-FileCopyrightText: 2026 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

require 'prawn'
require 'prawn/table'
require 'rqrcode'

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

  def links_section
    section_header('Related Links')
    move_down 8

    qr_size = 60

    @incident_report.links.ordered.each do |link|
      # Remember the starting position
      start_y = cursor

      # Generate QR code
      qr_png = generate_qr_png(link.url)

      if qr_png
        # Draw QR code at current position
        image StringIO.new(qr_png), width: qr_size, height: qr_size, position: :left

        # Move back up to draw text next to QR code
        move_up qr_size - 5

        # Draw text indented past the QR code
        indent(qr_size + 15) do
          text link.title, size: 11, style: :bold
          move_down 3
          text link.url, size: 9, color: '0066CC'
        end

        # Ensure we move past the QR code
        move_down [0, start_y - cursor - qr_size - 10].min.abs
      else
        # No QR code, just show text
        text "• #{link.title}", size: 11, style: :bold
        text "  #{link.url}", size: 9, color: '0066CC'
      end

      move_down 12
    end
  end

  def generate_qr_png(url)
    qr = RQRCode::QRCode.new(url)
    png = qr.as_png(
      size: 200,
      border_modules: 1,
      color: '000000',
      fill: 'ffffff'
    )
    png.to_s
  rescue StandardError => e
    Rails.logger.error("Failed to generate QR code for #{url}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
    nil
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
