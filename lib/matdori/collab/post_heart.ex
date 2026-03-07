defmodule Matdori.Collab.PostHeart do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.Post

  schema "post_hearts" do
    field :session_id, :string
    field :google_uid, :string
    field :kind, :string, default: "like"

    belongs_to :post, Post

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(heart, attrs) do
    heart
    |> cast(attrs, [:post_id, :session_id, :google_uid, :kind])
    |> validate_required([:post_id, :session_id, :kind])
    |> validate_inclusion(:kind, ["like", "dislike"])
    |> unique_constraint([:post_id, :session_id])
    |> check_constraint(:kind, name: :post_hearts_kind_check)
  end
end
