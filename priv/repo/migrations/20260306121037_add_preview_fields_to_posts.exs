defmodule Matdori.Repo.Migrations.AddPreviewFieldsToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :preview_title, :string
      add :preview_description, :string
      add :preview_image_url, :string
    end
  end
end
