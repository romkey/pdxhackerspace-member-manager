class AccessControllerPayloadBuilder
  def self.call
    users = User.active.includes(:rfids, trainings_as_trainee: :training_topic)

    data = users.map do |user|
      {
        name: user.full_name.presence || user.display_name,
        uid: user.authentik_id.presence || user.id,
        greeting_name: user.greeting_name,
        rfids: user.rfids.map(&:rfid),
        permissions: user.trainings_as_trainee.map { |training| training.training_topic&.name }.compact.uniq
      }
    end

    JSON.generate(data)
  end
end
