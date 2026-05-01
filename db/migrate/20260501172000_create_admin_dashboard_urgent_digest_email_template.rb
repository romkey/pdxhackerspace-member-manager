# frozen_string_literal: true

class CreateAdminDashboardUrgentDigestEmailTemplate < ActiveRecord::Migration[8.1]
  def up
    return if EmailTemplate.exists?(key: 'admin_dashboard_urgent_digest')

    attrs = EmailTemplate::DEFAULT_TEMPLATES['admin_dashboard_urgent_digest']
    EmailTemplate.create!({ key: 'admin_dashboard_urgent_digest' }.merge(attrs))
  end

  def down
    EmailTemplate.where(key: 'admin_dashboard_urgent_digest').delete_all
  end
end
