defmodule Matdori.Repo.Migrations.AddGoogleUidTrackingToCollabEntities do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :creator_google_uid, :string
    end

    create index(:posts, [:creator_google_uid])

    alter table(:post_hearts) do
      add :google_uid, :string
    end

    create index(:post_hearts, [:google_uid])
    create index(:post_hearts, [:google_uid, :kind])

    alter table(:highlights) do
      add :google_uid, :string
    end

    create index(:highlights, [:google_uid])
  end
end
