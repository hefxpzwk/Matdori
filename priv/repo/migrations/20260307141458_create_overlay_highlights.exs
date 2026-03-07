defmodule Matdori.Repo.Migrations.CreateOverlayHighlights do
  use Ecto.Migration

  def change do
    create table(:overlay_highlights) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :highlight_key, :string, null: false
      add :session_id, :string, null: false
      add :display_name, :string, null: false
      add :color, :string, null: false
      add :left, :float, null: false
      add :top, :float, null: false
      add :width, :float, null: false
      add :height, :float, null: false
      add :comment, :text, null: false, default: ""

      timestamps(type: :utc_datetime_usec)
    end

    create index(:overlay_highlights, [:post_id])
    create index(:overlay_highlights, [:post_id, :session_id])
    create unique_index(:overlay_highlights, [:post_id, :highlight_key])
  end
end
