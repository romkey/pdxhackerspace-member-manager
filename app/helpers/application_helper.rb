module ApplicationHelper
  def bootstrap_class_for(flash_type)
    {
      "notice" => "success",
      "alert" => "warning",
      "error" => "danger",
      "info" => "info"
    }.fetch(flash_type.to_s, "secondary")
  end
end
