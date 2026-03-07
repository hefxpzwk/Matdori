defmodule Matdori.Collab.OverlayHighlight do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.Post

  schema "overlay_highlights" do
    field :highlight_key, :string
    field :session_id, :string
    field :display_name, :string
    field :color, :string
    field :left, :float
    field :top, :float
    field :width, :float
    field :height, :float
    field :comment, :string, default: ""

    belongs_to :post, Post

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(highlight, attrs) do
    highlight
    |> cast(attrs, [
      :post_id,
      :highlight_key,
      :session_id,
      :display_name,
      :color,
      :left,
      :top,
      :width,
      :height,
      :comment
    ])
    |> validate_required([
      :post_id,
      :highlight_key,
      :session_id,
      :display_name,
      :color,
      :left,
      :top,
      :width,
      :height
    ])
    |> validate_length(:highlight_key, min: 1, max: 80)
    |> validate_length(:display_name, min: 1, max: 30)
    |> validate_length(:comment, max: 240)
    |> validate_number(:left, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:top, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:width, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:height, greater_than: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:post_id)
    |> unique_constraint([:post_id, :highlight_key])
  end
end
