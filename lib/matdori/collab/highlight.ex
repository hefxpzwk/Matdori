defmodule Matdori.Collab.Highlight do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.{PostSnapshot, Comment}

  schema "highlights" do
    field :session_id, :string
    field :google_uid, :string
    field :display_name, :string
    field :color, :string
    field :quote_exact, :string
    field :quote_prefix, :string
    field :quote_suffix, :string
    field :start_g, :integer
    field :end_g, :integer

    belongs_to :post_snapshot, PostSnapshot
    has_many :comments, Comment

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(highlight, attrs) do
    highlight
    |> cast(attrs, [
      :post_snapshot_id,
      :session_id,
      :google_uid,
      :display_name,
      :color,
      :quote_exact,
      :quote_prefix,
      :quote_suffix,
      :start_g,
      :end_g
    ])
    |> validate_required([
      :post_snapshot_id,
      :session_id,
      :display_name,
      :color,
      :quote_exact,
      :start_g,
      :end_g
    ])
    |> validate_number(:start_g, greater_than_or_equal_to: 0)
    |> validate_number(:end_g, greater_than: 0)
    |> validate_start_end()
    |> foreign_key_constraint(:post_snapshot_id)
  end

  defp validate_start_end(changeset) do
    start_g = get_field(changeset, :start_g)
    end_g = get_field(changeset, :end_g)

    if is_integer(start_g) and is_integer(end_g) and end_g <= start_g do
      add_error(changeset, :end_g, "must be greater than start_g")
    else
      changeset
    end
  end
end
