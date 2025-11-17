class MakeTrainerIdNullableInTrainings < ActiveRecord::Migration[7.1]
  def change
    change_column_null :trainings, :trainer_id, true
  end
end
