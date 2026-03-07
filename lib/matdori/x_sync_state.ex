defmodule Matdori.XSyncState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "x_sync_states" do
    field :source_username, :string
    field :backfill_next_token, :string
    field :backfill_completed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(state, attrs) do
    state
    |> cast(attrs, [:source_username, :backfill_next_token, :backfill_completed_at])
    |> validate_required([:source_username])
    |> unique_constraint(:source_username)
  end
end
