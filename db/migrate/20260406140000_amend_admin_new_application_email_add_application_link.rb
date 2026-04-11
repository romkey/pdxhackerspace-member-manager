# frozen_string_literal: true

class AmendAdminNewApplicationEmailAddApplicationLink < ActiveRecord::Migration[8.1]
  def up
    tpl = EmailTemplate.find_by(key: 'admin_new_application')
    return unless tpl

    attrs = EmailTemplate::DEFAULT_TEMPLATES['admin_new_application']
    tpl.update!(body_html: attrs[:body_html], body_text: attrs[:body_text])
  end

  def down
    # Non-reversible; prior bodies were site-specific.
  end
end
