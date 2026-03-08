defmodule Matdori.Repo.Migrations.AddProfileColorAndCommentColor do
  use Ecto.Migration

  def change do
    alter table(:user_profiles) do
      add :color, :string
    end

    alter table(:comments) do
      add :color, :string
    end
  end
end
