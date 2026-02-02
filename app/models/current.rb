class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :skip_authentik_sync
end
