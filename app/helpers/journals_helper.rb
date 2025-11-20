module JournalsHelper
  def render_change_rows(changes_hash)
    return content_tag(:span, 'No field changes recorded', class: 'text-muted') if changes_hash.blank?

    content_tag(:div, class: 'table-responsive') do
      content_tag(:table, class: 'table table-sm mb-0 align-middle') do
        thead = content_tag(:thead, class: 'bg-body-tertiary') do
          content_tag(:tr) do
            content_tag(:th, 'Field') +
              content_tag(:th, 'From') +
              content_tag(:th, 'To')
          end
        end

        tbody = content_tag(:tbody) do
          changes_hash.map do |attr, vals|
            content_tag(:tr) do
              content_tag(:td, attr.humanize) +
                content_tag(:td, display_change_value(vals['from'])) +
                content_tag(:td, display_change_value(vals['to']))
            end
          end.join.html_safe
        end

        thead + tbody
      end
    end
  end

  def display_change_value(value)
    case value
    when nil
      content_tag(:span, 'nil', class: 'text-muted fst-italic')
    when ''
      content_tag(:span, 'empty', class: 'text-muted fst-italic')
    else
      if value.is_a?(TrueClass) || value.is_a?(FalseClass)
        value ? 'true' : 'false'
      else
        value.to_s
      end
    end
  end
end
