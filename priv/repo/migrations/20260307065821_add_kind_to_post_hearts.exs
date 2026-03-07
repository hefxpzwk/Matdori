defmodule Matdori.Repo.Migrations.AddKindToPostHearts do
  use Ecto.Migration

  def change do
    alter table(:post_hearts) do
      add :kind, :string, null: false, default: "like"
    end

    create constraint(:post_hearts, :post_hearts_kind_check, check: "kind IN ('like', 'dislike')")
  end
end
