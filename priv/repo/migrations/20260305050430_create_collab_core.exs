defmodule Matdori.Repo.Migrations.CreateCollabCore do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :tweet_url, :string, null: false
      add :tweet_id, :string
      add :room_date, :date, null: false
      add :hidden, :boolean, null: false, default: false
      add :hidden_reason, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:posts, [:room_date])
    create unique_index(:posts, [:tweet_url])

    create table(:post_snapshots) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :normalized_text, :text, null: false
      add :submitted_by_session_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:post_snapshots, [:post_id, :version])

    alter table(:posts) do
      add :current_snapshot_id, references(:post_snapshots, on_delete: :nilify_all)
    end

    create index(:posts, [:current_snapshot_id])

    create table(:highlights) do
      add :post_snapshot_id, references(:post_snapshots, on_delete: :delete_all), null: false
      add :session_id, :string, null: false
      add :display_name, :string, null: false
      add :color, :string, null: false
      add :quote_exact, :text, null: false
      add :quote_prefix, :text
      add :quote_suffix, :text
      add :start_g, :integer, null: false
      add :end_g, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:highlights, [:post_snapshot_id])
    create index(:highlights, [:post_snapshot_id, :start_g, :end_g])

    create table(:comments) do
      add :highlight_id, references(:highlights, on_delete: :delete_all), null: false
      add :session_id, :string, null: false
      add :display_name, :string, null: false
      add :body, :text, null: false
      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:comments, [:highlight_id])
    create index(:comments, [:highlight_id, :inserted_at])

    create table(:post_hearts) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :session_id, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:post_hearts, [:post_id, :session_id])

    create table(:reports) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :session_id, :string, null: false
      add :display_name, :string, null: false
      add :reason, :text, null: false
      add :status, :string, null: false, default: "open"

      timestamps(type: :utc_datetime_usec)
    end

    create index(:reports, [:post_id])
    create index(:reports, [:status])
  end
end
