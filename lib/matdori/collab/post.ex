defmodule Matdori.Collab.Post do
  use Ecto.Schema
  import Ecto.Changeset

  alias Matdori.Collab.{PostSnapshot, PostHeart, Report}

  schema "posts" do
    field :tweet_url, :string
    field :tweet_id, :string
    field :tweet_posted_at, :utc_datetime_usec
    field :room_date, :date
    field :hidden, :boolean, default: false
    field :hidden_reason, :string

    belongs_to :current_snapshot, PostSnapshot
    has_many :snapshots, PostSnapshot
    has_many :hearts, PostHeart
    has_many :reports, Report

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [
      :tweet_url,
      :tweet_id,
      :tweet_posted_at,
      :room_date,
      :hidden,
      :hidden_reason,
      :current_snapshot_id
    ])
    |> validate_required([:tweet_url, :room_date])
    |> unique_constraint(:tweet_url)
  end
end
