defmodule Matdori.Repo.Migrations.AddAvatarUrlToUserProfiles do
  use Ecto.Migration

  def change do
    alter table(:user_profiles) do
      add :avatar_url, :string
    end
  end
end
