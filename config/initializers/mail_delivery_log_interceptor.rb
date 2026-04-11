# frozen_string_literal: true

# Action Mailer 8.1+ no longer exposes +delivery_interceptors+ on +ActionMailer::Base+;
# registration delegates to the Mail gem, which skips duplicates.
Rails.application.config.after_initialize do
  ActionMailer::Base.register_interceptor(MailDeliveryLogInterceptor)
end
