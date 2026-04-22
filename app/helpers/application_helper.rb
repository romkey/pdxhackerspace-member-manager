module ApplicationHelper
  require 'digest'

  def bootstrap_class_for(flash_type)
    {
      'notice' => 'success',
      'alert' => 'warning',
      'error' => 'danger',
      'info' => 'info'
    }.fetch(flash_type.to_s, 'secondary')
  end

  MEMBERSHIP_STATUS_BADGE_CLASSES = {
    'paying' => 'success',
    'guest' => 'warning',
    'banned' => 'danger',
    'deceased' => 'dark',
    'sponsored' => 'primary',
    'applicant' => 'light text-dark',
    'cancelled' => 'secondary',
    'unknown' => 'secondary'
  }.freeze

  DUES_STATUS_BADGE_CLASSES = {
    'current' => 'success',
    'lapsed' => 'warning',
    'inactive' => 'secondary',
    'unknown' => 'secondary'
  }.freeze

  def membership_status_badge_class(status)
    MEMBERSHIP_STATUS_BADGE_CLASSES.fetch(status.to_s, 'secondary')
  end

  def dues_status_badge_class(status)
    DUES_STATUS_BADGE_CLASSES.fetch(status.to_s, 'secondary')
  end

  def gravatar_url(email, size: 32)
    return nil if email.blank?

    hash = Digest::MD5.hexdigest(email.downcase.strip)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=mp"
  end

  def smtp_configured?
    settings = Rails.configuration.action_mailer.smtp_settings
    return false unless settings.is_a?(Hash)

    settings[:address].present? &&
      settings[:address] != 'smtp.example.com' &&
      settings[:user_name].present? &&
      settings[:password].present?
  end

  # Sanitize a URL to only allow http/https schemes, returning '#' for unsafe URLs.
  # Prevents stored XSS via javascript: or data: URLs in link hrefs.
  def sanitize_url(url)
    return '#' if url.blank?

    parsed = URI.parse(url.to_s)
    %w[http https].include?(parsed.scheme) ? url.to_s : '#'
  rescue URI::InvalidURIError
    '#'
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

  # Membership application show: full applicant/referrer contact visibility (Executive Director training).
  def membership_application_contact_pii_visible?(user = current_user)
    return true if user.blank?

    topic = TrainingTopic.where('LOWER(name) = ?', MembershipApplication::EXECUTIVE_DIRECTOR_TRAINING_TOPIC_NAME.downcase).first
    return true if topic.nil?

    Training.exists?(trainee: user, training_topic: topic)
  end

  def membership_application_mask_contact_pii?
    !membership_application_contact_pii_visible?
  end

  def membership_application_sensitive_answer_label?(label)
    MembershipApplication::FORM_ANSWER_LABELS_CONTACT_SENSITIVE.include?(label.to_s.strip)
  end

  # Wrap block output when contact PII should be masked (blur + reveal toggle on ancestor).
  def membership_application_masked_contact_capture(&)
    html = capture(&)
    if membership_application_mask_contact_pii?
      content_tag(:span, html,
                  class: 'd-inline-block w-100',
                  data: { sensitive_reveal_target: 'blurred' })
    else
      html
    end
  end
end
