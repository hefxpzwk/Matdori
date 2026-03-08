defmodule Matdori.Repo.Migrations.AddPostIdToCommentsForRoomComments do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      modify :highlight_id, :bigint, null: true
      add :post_id, references(:posts, on_delete: :delete_all)
    end

    create index(:comments, [:post_id])
    create index(:comments, [:post_id, :inserted_at])

    create constraint(:comments, :comments_target_required,
             check:
               "(highlight_id IS NOT NULL AND post_id IS NULL) OR (highlight_id IS NULL AND post_id IS NOT NULL)"
           )
  end
end
