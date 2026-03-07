defmodule Matdori.Collab.PostView do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.Post

  schema "post_views" do
    field :session_id, :string

    belongs_to :post, Post

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(view, attrs) do
    view
    |> cast(attrs, [:post_id, :session_id])
    |> validate_required([:post_id, :session_id])
    |> unique_constraint([:post_id, :session_id])
  end
end
