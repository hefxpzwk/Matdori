defmodule Matdori.Collab.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.Highlight

  schema "comments" do
    field :session_id, :string
    field :google_uid, :string
    field :display_name, :string
    field :body, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :highlight, Highlight

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:highlight_id, :session_id, :google_uid, :display_name, :body, :deleted_at])
    |> validate_required([:highlight_id, :session_id, :display_name, :body])
    |> validate_length(:body, min: 1, max: 500)
    |> foreign_key_constraint(:highlight_id)
  end
end
