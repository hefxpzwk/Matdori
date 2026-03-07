defmodule Matdori.Repo.Migrations.AddGoogleUidToCommentsAndReports do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      add :google_uid, :string
    end

    alter table(:reports) do
      add :google_uid, :string
    end

    create index(:comments, [:google_uid])
    create index(:reports, [:google_uid])
  end
end
