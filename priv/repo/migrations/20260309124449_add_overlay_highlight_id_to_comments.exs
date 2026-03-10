defmodule Matdori.Repo.Migrations.AddOverlayHighlightIdToComments do
  use Ecto.Migration

  def up do
    alter table(:comments) do
      add :overlay_highlight_id, references(:overlay_highlights, on_delete: :delete_all)
    end

    create index(:comments, [:overlay_highlight_id])
    create index(:comments, [:overlay_highlight_id, :inserted_at])

    execute("ALTER TABLE comments DROP CONSTRAINT IF EXISTS comments_target_required")

    create constraint(:comments, :comments_target_required,
             check:
               "(highlight_id IS NOT NULL AND post_id IS NULL AND overlay_highlight_id IS NULL) OR " <>
                 "(highlight_id IS NULL AND post_id IS NOT NULL AND overlay_highlight_id IS NULL) OR " <>
                 "(highlight_id IS NULL AND post_id IS NULL AND overlay_highlight_id IS NOT NULL)"
           )
  end

  def down do
    drop constraint(:comments, :comments_target_required)

    drop index(:comments, [:overlay_highlight_id, :inserted_at])
    drop index(:comments, [:overlay_highlight_id])

    alter table(:comments) do
      remove :overlay_highlight_id
    end

    create constraint(:comments, :comments_target_required,
             check:
               "(highlight_id IS NOT NULL AND post_id IS NULL) OR (highlight_id IS NULL AND post_id IS NOT NULL)"
           )
  end
end
