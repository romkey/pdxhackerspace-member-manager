module ApplicationHelper
  require 'digest'

  def bootstrap_class_for(flash_type)
    {
      'notice' => 'success',
      'alert' => 'warning',
      'error' => 'danger',
      'info' => 'info'
    }.fetch(flash_type.to_s, 'secondary')
  end

  def gravatar_url(email, size: 32)
    return nil if email.blank?

    hash = Digest::MD5.hexdigest(email.downcase.strip)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=mp"
  end
end
