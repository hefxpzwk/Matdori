defmodule Matdori.Collab.Post do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.{PostSnapshot, PostHeart, PostView, Report}

  schema "posts" do
    field :title, :string
    field :preview_title, :string
    field :preview_description, :string
    field :preview_image_url, :string
    field :tweet_url, :string
    field :tweet_id, :string
    field :tweet_posted_at, :utc_datetime_usec
    field :room_date, :date
    field :hidden, :boolean, default: false
    field :hidden_reason, :string
    field :like_count, :integer, virtual: true, default: 0
    field :dislike_count, :integer, virtual: true, default: 0
    field :view_count, :integer, virtual: true, default: 0

    belongs_to :current_snapshot, PostSnapshot
    has_many :snapshots, PostSnapshot
    has_many :hearts, PostHeart
    has_many :views, PostView
    has_many :reports, Report

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :title,
      :preview_title,
      :preview_description,
      :preview_image_url,
      :tweet_url,
      :tweet_id,
      :tweet_posted_at,
      :room_date,
      :hidden,
      :hidden_reason,
      :current_snapshot_id
    ])
    |> validate_required([:tweet_url, :tweet_id, :room_date])
    |> unique_constraint(:tweet_url)
    |> unique_constraint(:tweet_id)
  end
end
