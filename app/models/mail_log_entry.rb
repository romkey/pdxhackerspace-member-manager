class MailLogEntry < ApplicationRecord
  EVENTS = %w[created edited regenerated approved rejected sent send_failed].freeze

  belongs_to :queued_mail
  belongs_to :actor, class_name: 'User', optional: true

  validates :event, presence: true, inclusion: { in: EVENTS }

  scope :newest_first, -> { order(created_at: :desc) }
  scope :oldest_first, -> { order(created_at: :asc) }

  def self.log!(queued_mail, event, actor: nil, details: nil)
    create!(
      queued_mail: queued_mail,
      event: event,
      actor: actor,
      details: details
    )
  end

  def self.log_once!(queued_mail, event, actor: nil, details: nil)
    last_entry = queued_mail.mail_log_entries
                            .where(event: event)
                            .order(created_at: :desc)
                            .first

    return if last_entry && last_entry.details == details

    log!(queued_mail, event, actor: actor, details: details)
  end

  def wait_duration
    return nil unless event.in?(%w[approved rejected sent])

    queued_mail.created_at ? (created_at - queued_mail.created_at) : nil
  end

  def wait_duration_in_words
    seconds = wait_duration
    return nil unless seconds

    if seconds < 60
      "less than a minute"
    elsif seconds < 3600
      "#{(seconds / 60).round} minutes"
    elsif seconds < 86_400
      hours = (seconds / 3600).round
      "#{hours} #{'hour'.pluralize(hours)}"
    else
      days = (seconds / 86_400).round
      "#{days} #{'day'.pluralize(days)}"
    end
  end
end
