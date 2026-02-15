# Shared concern for finding users by name (including aliases)
# and automatically recording differing names as aliases.
module UserNameMatcher
  private

  # Find a user by name, checking both full_name and aliases.
  # If found and the name differs from full_name, adds it as an alias.
  def find_user_by_name(name)
    return nil if name.blank?

    normalized = name.to_s.strip
    return nil if normalized.blank?

    user = User.by_name_or_alias(normalized).first
    return nil unless user

    # Auto-add differing name as alias
    user.add_alias!(normalized) if user.full_name.present? && user.full_name.strip.downcase != normalized.downcase

    user
  end
end
