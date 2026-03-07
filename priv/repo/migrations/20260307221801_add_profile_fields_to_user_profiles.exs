defmodule Matdori.Repo.Migrations.AddProfileFieldsToUserProfiles do
  use Ecto.Migration

  def change do
    alter table(:user_profiles) do
      add :display_name, :string
      add :interests, {:array, :string}, null: false, default: []
    end

    execute(
      """
      UPDATE user_profiles
      SET interests = CASE
        WHEN interest IS NULL OR btrim(interest) = '' THEN ARRAY[]::varchar[]
        ELSE ARRAY[btrim(interest)]
      END
      """,
      """
      UPDATE user_profiles
      SET interest = CASE
        WHEN array_length(interests, 1) IS NULL OR array_length(interests, 1) = 0 THEN ''
        ELSE interests[1]
      END
      """
    )
  end
end
