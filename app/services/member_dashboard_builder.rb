class MemberDashboardBuilder
  def initialize(user:, due_soon_days:, path_for_tab:)
    @user = user
    @due_soon_days = due_soon_days
    @path_for_tab = path_for_tab
  end

  def build
    items = [
      payment_item,
      messages_item,
      training_item,
      slack_item,
      parking_item
    ]

    {
      attention_items: items.reject { |item| item[:ok] },
      ok_items: items.select { |item| item[:ok] }
    }
  end

  private

  attr_reader :user, :due_soon_days, :path_for_tab

  def payment_item
    return payment_not_manual_item unless manual_payment?

    due_on = user.next_payment_date
    return payment_missing_due_date_item if due_on.blank?

    days_until = (due_on - Date.current).to_i
    return payment_overdue_item(due_on, days_until) if days_until.negative?
    return payment_due_soon_item(due_on, days_until) if days_until <= due_soon_days

    payment_ok_item(due_on, days_until)
  end

  def payment_not_manual_item
    ok_item(:cash_payment_due, 'Cash payment due', 'You are not on a manual/cash payment plan.')
  end

  def payment_missing_due_date_item
    attention_item(
      tier: :housekeeping,
      id: :cash_payment_due,
      title: 'Cash payment due',
      detail: 'No next payment due date is recorded yet. Please contact an admin.',
      action: {
        label: 'Open Payments tab',
        path: tab_path(:payments)
      }
    )
  end

  def payment_overdue_item(due_on, days_until)
    attention_item(
      tier: :urgent,
      id: :cash_payment_due,
      title: 'Cash payment due',
      detail: "Your next cash payment was due #{date_text(due_on)} (#{days_until.abs} days overdue).",
      action: {
        label: 'Open Payments tab',
        path: tab_path(:payments)
      }
    )
  end

  def payment_due_soon_item(due_on, days_until)
    attention_item(
      tier: :important,
      id: :cash_payment_due,
      title: 'Cash payment due soon',
      detail: "Your next cash payment is due in #{days_until} days (#{date_text(due_on)}).",
      action: {
        label: 'Open Payments tab',
        path: tab_path(:payments)
      }
    )
  end

  def payment_ok_item(due_on, days_until)
    ok_item(
      :cash_payment_due,
      'Cash payment due',
      "Your next cash payment is due in #{days_until} days (#{date_text(due_on)})."
    )
  end

  def messages_item
    unread_count = Message.folder(user, :unread).count
    return messages_unread_item(unread_count) if unread_count.positive?

    ok_item(:unread_messages, 'Unread messages', 'You have no unread messages.')
  end

  def messages_unread_item(unread_count)
    attention_item(
      tier: :urgent,
      id: :unread_messages,
      title: 'Unread messages',
      detail: "You have #{unread_count} unread message#{'s' unless unread_count == 1}.",
      action: {
        label: 'Open Messages',
        path: Rails.application.routes.url_helpers.messages_path(folder: :unread)
      }
    )
  end

  def training_item
    pending_count = user.training_requests.pending.count
    return training_pending_item(pending_count) if pending_count.positive?

    ok_item(:training_requests, 'Open training requests', 'You have no open training requests.')
  end

  def training_pending_item(pending_count)
    attention_item(
      tier: :important,
      id: :training_requests,
      title: 'Open training requests',
      detail: "You have #{pending_count} open training request#{'s' unless pending_count == 1}.",
      action: {
        label: 'Open Profile tab',
        path: tab_path(:profile)
      }
    )
  end

  def slack_item
    return ok_item(:slack_signup, 'Slack account', 'Your account is linked to Slack.') if user.slack_user.present?

    if SlackOidcConfig.configured?
      attention_item(
        tier: :housekeeping,
        id: :slack_signup,
        title: 'Slack account',
        detail: 'Link your CTRLH Slack workspace member to your profile so we can recognize you on Slack.',
        action: {
          label: 'Associate Slack account',
          path: Rails.application.routes.url_helpers.slack_link_start_path
        }
      )
    else
      attention_item(
        tier: :housekeeping,
        id: :slack_signup,
        title: 'Join Slack',
        detail: 'You do not have a linked Slack user yet. Please ask an admin for an invite.',
        action: {
          label: 'Open Profile tab',
          path: tab_path(:profile)
        }
      )
    end
  end

  def parking_item
    notices = user.parking_notices.not_cleared
    expired_count = notices.expired_notices.count
    active_count = notices.active_notices.count

    return parking_expired_item(expired_count, active_count) if expired_count.positive?
    return parking_active_item(active_count) if active_count.positive?

    ok_item(
      :parking_notices,
      'Open parking permits/tickets',
      'You have no open parking permits or tickets.'
    )
  end

  def parking_expired_item(expired_count, active_count)
    total_count = expired_count + active_count
    attention_item(
      tier: :urgent,
      id: :parking_notices,
      title: 'Open parking permits/tickets',
      detail: "#{expired_count} expired and #{active_count} active open parking notice#{'s' unless total_count == 1}.",
      action: {
        label: 'Open Parking tab',
        path: tab_path(:parking)
      }
    )
  end

  def parking_active_item(active_count)
    attention_item(
      tier: :important,
      id: :parking_notices,
      title: 'Open parking permits/tickets',
      detail: "#{active_count} active open parking notice#{'s' unless active_count == 1}.",
      action: {
        label: 'Open Parking tab',
        path: tab_path(:parking)
      }
    )
  end

  def manual_payment?
    return true if user.payment_type == 'cash'

    user.all_membership_plans.any?(&:manual?)
  end

  def attention_item(tier:, id:, title:, detail:, action:)
    {
      ok: false,
      tier: tier,
      id: id,
      title: title,
      detail: detail,
      action_label: action[:label],
      action_path: action[:path]
    }
  end

  def ok_item(id, title, detail)
    {
      ok: true,
      tier: :none,
      id: id,
      title: title,
      detail: detail
    }
  end

  def date_text(date)
    date.strftime('%B %-d, %Y')
  end

  def tab_path(tab)
    path_for_tab.call(tab)
  end
end
