defmodule Matdori.Repo.Migrations.AddGoogleUidToOverlayHighlights do
  use Ecto.Migration

  def change do
    alter table(:overlay_highlights) do
      add :google_uid, :string
    end

    create index(:overlay_highlights, [:google_uid])
  end
end
