defmodule Matdori.Repo.Migrations.AllowMultiplePostsPerDay do
  use Ecto.Migration

  def up do
    drop_if_exists unique_index(:posts, [:room_date])

    alter table(:posts) do
      add :tweet_posted_at, :utc_datetime_usec
    end

    create index(:posts, [:tweet_posted_at])
  end

  def down do
    drop_if_exists index(:posts, [:tweet_posted_at])

    alter table(:posts) do
      remove :tweet_posted_at
    end

    create unique_index(:posts, [:room_date])
  end
end
