module AppVersion
  def self.current
    return ENV["APP_VERSION"] if ENV["APP_VERSION"].present?

    begin
      git_dir = Rails.root.join(".git")
      if git_dir.exist?
        # Prefer annotated tags if available, else fallback to short SHA
        ver = `git describe --tags --always --dirty`.to_s.strip
        return ver if ver.present?
        sha = `git rev-parse --short HEAD`.to_s.strip
        return sha if sha.present?
      end
    rescue StandardError
      # ignore
    end

    "dev"
  end
end


