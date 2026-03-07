defmodule Matdori.Repo.Migrations.EnforceUniqueTweetIdOnPosts do
  use Ecto.Migration

  def up do
    execute("""
    UPDATE posts
    SET tweet_id = COALESCE(
      SUBSTRING(tweet_url FROM '/status/([0-9]+)'),
      'legacy-' || id::text
    )
    WHERE tweet_id IS NULL OR btrim(tweet_id) = ''
    """)

    execute("""
    WITH ranked AS (
      SELECT id, tweet_id,
             ROW_NUMBER() OVER (PARTITION BY tweet_id ORDER BY id) AS rn
      FROM posts
      WHERE tweet_id IS NOT NULL AND btrim(tweet_id) <> ''
    )
    UPDATE posts AS p
    SET tweet_id = p.tweet_id || '-dup-' || p.id::text
    FROM ranked AS r
    WHERE p.id = r.id AND r.rn > 1
    """)

    alter table(:posts) do
      modify :tweet_id, :string, null: false
    end

    create unique_index(:posts, [:tweet_id])
  end

  def down do
    drop_if_exists unique_index(:posts, [:tweet_id])

    alter table(:posts) do
      modify :tweet_id, :string, null: true
    end
  end
end
