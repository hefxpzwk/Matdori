defmodule Matdori.Repo.Migrations.CreateXSyncStates do
  use Ecto.Migration

  def change do
    create table(:x_sync_states) do
      add :source_username, :string, null: false
      add :backfill_next_token, :text
      add :backfill_completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:x_sync_states, [:source_username])
  end
end
