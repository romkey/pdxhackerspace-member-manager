module Api
  class UsersController < AdminController
    def search
      q = params[:q].to_s.strip
      
      if q.blank?
        render json: []
        return
      end
      
      pattern = "%#{q.downcase}%"
      
      users = User.where(
        "LOWER(COALESCE(full_name, '')) LIKE :p OR LOWER(COALESCE(email, '')) LIKE :p OR LOWER(COALESCE(username, '')) LIKE :p",
        p: pattern
      ).order(:full_name).limit(20)
      
      render json: users.map { |u| { id: u.id, name: u.display_name, email: u.email } }
    end
  end
end
