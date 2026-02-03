module ApplicationHelper
  include Pagy::Frontend
  require 'digest'

  def bootstrap_class_for(flash_type)
    {
      'notice' => 'success',
      'alert' => 'warning',
      'error' => 'danger',
      'info' => 'info'
    }.fetch(flash_type.to_s, 'secondary')
  end

  def gravatar_url(email, size: 32)
    return nil if email.blank?

    hash = Digest::MD5.hexdigest(email.downcase.strip)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=mp"
  end

  # Generate a sortable column header link
  # @param column [String] the database column to sort by
  # @param title [String] the display text for the header
  # @param current_sort [String] the current sort column
  # @param current_direction [String] the current sort direction ('asc' or 'desc')
  def sortable_column(column, title, current_sort, current_direction)
    is_current = column == current_sort
    new_direction = is_current && current_direction == 'asc' ? 'desc' : 'asc'

    # Preserve existing query params (filters, etc.)
    sort_params = request.query_parameters.merge(sort: column, direction: new_direction)

    icon = if is_current
             current_direction == 'asc' ? 'bi-sort-up' : 'bi-sort-down'
           else
             'bi-arrow-down-up'
           end

    link_class = is_current ? 'text-primary text-decoration-none fw-bold' : 'text-body text-decoration-none'

    link_to(sort_params, class: link_class) do
      safe_join([title, ' ', content_tag(:i, '', class: "bi #{icon} small")])
    end
  end
end
