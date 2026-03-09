module IncidentReportsHelper
  def incident_type_badge_class(incident_type)
    case incident_type.to_s
    when 'code_of_conduct', 'theft'
      'danger'
    when 'damage', 'equipment_issue'
      'warning'
    when 'open_doors'
      'info'
    when 'other'
      'dark'
    else
      'secondary'
    end
  end
end
