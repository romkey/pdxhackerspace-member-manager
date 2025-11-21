class ApplicationGroup < ApplicationRecord
  belongs_to :application
  belongs_to :training_topic, optional: true
  has_and_belongs_to_many :users

  validates :name, presence: true
  validates :authentik_name, presence: true
  validates :training_topic_id, presence: true, if: -> { use_can_train? || use_trained_in? }

  before_save :ensure_mutual_exclusivity

  def uses_default_group?
    use_default_members_group? || use_default_admins_group? || use_can_train? || use_trained_in?
  end

  private

  def ensure_mutual_exclusivity
    # Count how many options are selected
    selected = [use_default_members_group?, use_default_admins_group?, use_can_train?, use_trained_in?].count(true)
    
    if selected > 1
      # If multiple are selected, keep only the one that was just changed
      if use_default_members_group_changed? && use_default_members_group?
        self.use_default_admins_group = false
        self.use_can_train = false
        self.use_trained_in = false
      elsif use_default_admins_group_changed? && use_default_admins_group?
        self.use_default_members_group = false
        self.use_can_train = false
        self.use_trained_in = false
      elsif use_can_train_changed? && use_can_train?
        self.use_default_members_group = false
        self.use_default_admins_group = false
        self.use_trained_in = false
      elsif use_trained_in_changed? && use_trained_in?
        self.use_default_members_group = false
        self.use_default_admins_group = false
        self.use_can_train = false
      end
    end
  end
end
