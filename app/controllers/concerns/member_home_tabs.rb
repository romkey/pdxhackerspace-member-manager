module MemberHomeTabs
  private

  def prepare_member_home_tabs_data
    set_member_dashboard_data
    set_self_service_training_data
    set_home_parking_data
    set_home_messages_data
    set_home_payments_data
  end

  def set_home_parking_data
    parking_query = @home_user.parking_notices.not_cleared.newest_first
    @home_parking_notices_count = parking_query.count
    @home_parking_notices_list = parking_query.limit(50)
  end

  def set_home_messages_data
    messages_query = @home_user.received_messages.includes(:sender).newest_first
    @home_messages_count = messages_query.count
    @home_unread_messages_count = @home_user.received_messages.unread.count

    return unless @active_tab == :messages

    @pagy_messages, @home_messages = pagy(messages_query, limit: 20, page_key: 'messages_page')
  end

  def set_home_payments_data
    payments_query = PaymentHistory.for_user(@home_user, event_type: params[:event_type].presence)
    @home_payments_count = payments_query.count

    return unless @active_tab == :payments

    @pagy_payments, @home_payments = pagy(payments_query, limit: 20, page_key: 'payments_page')
  end

  def set_self_service_training_data
    @member_requestable_topics = TrainingTopic.available_for_member_requests

    trainer_topic_ids = @home_user.training_topics.select(:id)
    ordering = 'training_topics.name ASC, training_requests.created_at DESC'
    trainer_requests = TrainingRequest.pending
                                      .where(training_topic_id: trainer_topic_ids)
                                      .joins(:training_topic)
                                      .includes(:training_topic, :user)
                                      .order(ordering)
    @trainer_training_requests_by_topic = trainer_requests.group_by(&:training_topic)
  end

  def set_member_dashboard_data
    items = MemberDashboardBuilder.new(
      user: @home_user,
      due_soon_days: MembershipSetting.manual_payment_due_soon_days,
      path_for_tab: ->(tab) { root_path(tab: tab) }
    ).build

    @member_dashboard_attention_items = items[:attention_items]
    @member_dashboard_ok_items = items[:ok_items]
  end
end
