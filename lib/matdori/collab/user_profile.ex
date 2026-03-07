defmodule Matdori.Collab.UserProfile do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_profiles" do
    field :google_uid, :string
    field :display_name, :string
    field :interest, :string, default: ""
    field :interests, {:array, :string}, default: []

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:google_uid, :display_name, :interest, :interests])
    |> validate_required([:google_uid])
    |> validate_length(:google_uid, max: 200)
    |> validate_length(:display_name, max: 30)
    |> validate_length(:interest, max: 160)
    |> validate_change(:interests, fn :interests, interests ->
      cond do
        !is_list(interests) -> [interests: "must be a list"]
        length(interests) > 12 -> [interests: "too many items"]
        true -> []
      end
    end)
    |> unique_constraint(:google_uid)
  end
end
