# SPDX-FileCopyrightText: 2026 John Romkey
#
# SPDX-License-Identifier: CC0-1.0

class AuthentikUser < ApplicationRecord
  belongs_to :user, optional: true

  validates :authentik_id, presence: true, uniqueness: true

  scope :linked, -> { where.not(user_id: nil) }
  scope :unlinked, -> { where(user_id: nil) }
  scope :active, -> { where(is_active: true) }
  scope :inactive, -> { where(is_active: false) }
  scope :with_discrepancies, lambda {
    joins(:user).where(
      "COALESCE(authentik_users.email, '') != COALESCE(users.email, '') OR " \
      "COALESCE(authentik_users.full_name, '') != COALESCE(users.full_name, '') OR " \
      "COALESCE(authentik_users.username, '') != COALESCE(users.username, '')"
    )
  }

  # Returns an array of field discrepancies between this AuthentikUser and its linked User
  def discrepancies
    return [] unless user

    diffs = []

    if normalize_value(email) != normalize_value(user.email)
      diffs << { field: 'email', authentik: email, user: user.email }
    end

    if normalize_value(full_name) != normalize_value(user.full_name)
      diffs << { field: 'full_name', authentik: full_name, user: user.full_name }
    end

    if normalize_value(username) != normalize_value(user.username)
      diffs << { field: 'username', authentik: username, user: user.username }
    end

    diffs
  end

  def has_discrepancies?
    discrepancies.any?
  end

  def display_name
    full_name.presence || username.presence || email.presence || authentik_id
  end

  private

  def normalize_value(value)
    value.to_s.strip.downcase
  end
end
