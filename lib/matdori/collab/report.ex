defmodule Matdori.Collab.Report do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.Post

  schema "reports" do
    field :session_id, :string
    field :google_uid, :string
    field :display_name, :string
    field :reason, :string
    field :status, :string, default: "open"

    belongs_to :post, Post

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(report, attrs) do
    report
    |> cast(attrs, [:post_id, :session_id, :google_uid, :display_name, :reason, :status])
    |> validate_required([:post_id, :session_id, :display_name, :reason])
    |> validate_length(:reason, min: 3, max: 600)
    |> foreign_key_constraint(:post_id)
  end
end
