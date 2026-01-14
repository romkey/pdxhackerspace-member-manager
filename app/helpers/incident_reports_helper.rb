module IncidentReportsHelper
  def incident_type_badge_class(incident_type)
    case incident_type.to_s
    when 'code_of_conduct'
      'danger'
    when 'theft'
      'danger'
    when 'damage'
      'warning'
    when 'equipment_issue'
      'warning'
    when 'open_doors'
      'info'
    when 'trash_issue'
      'secondary'
    when 'other'
      'dark'
    else
      'secondary'
    end
  end
end
