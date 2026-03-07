defmodule Matdori.Repo.Migrations.CreatePostViews do
  use Ecto.Migration

  def change do
    create table(:post_views) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :session_id, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:post_views, [:post_id])
    create unique_index(:post_views, [:post_id, :session_id])
  end
end
