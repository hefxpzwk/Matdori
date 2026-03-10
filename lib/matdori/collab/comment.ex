defmodule Matdori.Collab.Comment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.{Highlight, OverlayHighlight, Post}

  schema "comments" do
    field :session_id, :string
    field :google_uid, :string
    field :display_name, :string
    field :color, :string
    field :body, :string
    field :deleted_at, :utc_datetime_usec

    belongs_to :highlight, Highlight
    belongs_to :post, Post
    belongs_to :overlay_highlight, OverlayHighlight

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [
      :highlight_id,
      :post_id,
      :overlay_highlight_id,
      :session_id,
      :google_uid,
      :display_name,
      :color,
      :body,
      :deleted_at
    ])
    |> validate_required([:session_id, :display_name, :body])
    |> validate_comment_target()
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/)
    |> validate_length(:body, min: 1, max: 500)
    |> foreign_key_constraint(:highlight_id)
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:overlay_highlight_id)
    |> check_constraint(:highlight_id, name: :comments_target_required)
  end

  defp validate_comment_target(changeset) do
    highlight_id = get_field(changeset, :highlight_id)
    post_id = get_field(changeset, :post_id)
    overlay_highlight_id = get_field(changeset, :overlay_highlight_id)

    target_count =
      Enum.count([highlight_id, post_id, overlay_highlight_id], fn value -> not is_nil(value) end)

    cond do
      target_count == 0 ->
        add_error(changeset, :highlight_id, "or post_id or overlay_highlight_id is required")

      target_count > 1 ->
        add_error(changeset, :overlay_highlight_id, "must be the only target for this comment")

      true ->
        changeset
    end
  end
end
