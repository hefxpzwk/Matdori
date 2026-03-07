defmodule Matdori.Repo.Migrations.CreateUserProfiles do
  use Ecto.Migration

  def change do
    create table(:user_profiles) do
      add :google_uid, :string, null: false
      add :interest, :string, null: false, default: ""

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_profiles, [:google_uid])
  end
end
