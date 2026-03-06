defmodule Matdori.Collab.PostSnapshot do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.{Post, Highlight}

  schema "post_snapshots" do
    field :version, :integer
    field :normalized_text, :string
    field :submitted_by_session_id, :string

    belongs_to :post, Post
    has_many :highlights, Highlight

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:post_id, :version, :normalized_text, :submitted_by_session_id])
    |> validate_required([:post_id, :version, :normalized_text])
    |> unique_constraint([:post_id, :version])
    |> foreign_key_constraint(:post_id)
  end
end
