class RagController < ApplicationController
  def index
    render json: {
      interests: Interest.alphabetical.pluck(:name),
      training_topics: TrainingTopic.order(:name).pluck(:name)
    }
  end
end
