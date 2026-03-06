defmodule Matdori.Collab do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Matdori.Repo
  alias Matdori.TextAnchors
  alias Matdori.XTimeline
  alias Matdori.Collab.{Post, PostSnapshot, Highlight, Comment, PostHeart, Report}

  def today_date do
    DateTime.utc_now()
    |> DateTime.add(9 * 60 * 60, :second)
    |> DateTime.to_date()
  end

  def get_today_post do
    Repo.one(
      from p in Post,
        where: p.room_date == ^today_date(),
        order_by: [desc: fragment("COALESCE(?, ?)", p.tweet_posted_at, p.inserted_at), desc: p.id],
        limit: 1,
        preload: [:current_snapshot]
    )
  end

  def get_today_post_with_versions do
    case get_today_post() do
      nil ->
        nil

      post ->
        Repo.preload(post, [
          :current_snapshot,
          snapshots: from(s in PostSnapshot, order_by: [desc: s.version])
        ])
    end
  end

  def get_latest_post_with_versions do
    case Repo.one(
           from p in Post,
             order_by: [
               desc: fragment("COALESCE(?, ?)", p.tweet_posted_at, p.inserted_at),
               desc: p.id
             ],
             limit: 1
         ) do
      nil ->
        nil

      post ->
        Repo.preload(post, [
          :current_snapshot,
          snapshots: from(s in PostSnapshot, order_by: [desc: s.version])
        ])
    end
  end

  def get_post_with_versions(post_id) when is_integer(post_id) do
    case Repo.get(Post, post_id) do
      nil ->
        nil

      post ->
        Repo.preload(post, [
          :current_snapshot,
          snapshots: from(s in PostSnapshot, order_by: [desc: s.version])
        ])
    end
  end

  def list_posts(limit \\ 20) when is_integer(limit) and limit > 0 do
    Repo.all(
      from p in Post,
        order_by: [desc: fragment("COALESCE(?, ?)", p.tweet_posted_at, p.inserted_at), desc: p.id],
        limit: ^limit
    )
  end

  def sync_configured_account_posts(opts \\ []) do
    with {:ok, source_posts} <- source_posts(opts) do
      session_id = opts[:session_id] || "x-sync"

      {posts, errors} =
        Enum.reduce(source_posts, {[], []}, fn source_post, {acc_posts, acc_errors} ->
          case upsert_source_post(source_post, session_id) do
            {:ok, post} -> {[post | acc_posts], acc_errors}
            {:error, reason} -> {acc_posts, [reason | acc_errors]}
          end
        end)

      if posts == [] and errors != [] do
        {:error, {:sync_failed, Enum.reverse(errors)}}
      else
        {:ok, %{inserted_or_updated: length(posts), errors: Enum.reverse(errors)}}
      end
    end
  end

  def get_snapshot(post_id, version) do
    Repo.one(
      from s in PostSnapshot,
        where: s.post_id == ^post_id and s.version == ^version
    )
  end

  def latest_snapshot(post_id) do
    Repo.one(
      from s in PostSnapshot,
        where: s.post_id == ^post_id,
        order_by: [desc: s.version],
        limit: 1
    )
  end

  def upsert_today_post(attrs, session_id) do
    tweet_url = attrs["tweet_url"] || attrs[:tweet_url] || ""
    snapshot_text = attrs["snapshot_text"] || attrs[:snapshot_text] || ""
    normalized_text = TextAnchors.normalize(snapshot_text)

    if normalized_text == "" do
      {:error, :empty_snapshot}
    else
      post = get_today_post() || %Post{}

      latest_version =
        if post.id do
          case latest_snapshot(post.id) do
            nil -> 0
            snapshot -> snapshot.version
          end
        else
          0
        end

      next_version = latest_version + 1
      tweet_id = extract_tweet_id(tweet_url)

      Multi.new()
      |> Multi.insert_or_update(
        :post,
        Post.changeset(post, %{
          tweet_url: tweet_url,
          tweet_id: tweet_id,
          room_date: today_date(),
          hidden: false,
          hidden_reason: nil
        })
      )
      |> Multi.insert(:snapshot, fn %{post: updated_post} ->
        PostSnapshot.changeset(%PostSnapshot{}, %{
          post_id: updated_post.id,
          version: next_version,
          normalized_text: normalized_text,
          submitted_by_session_id: session_id
        })
      end)
      |> Multi.update(:set_current, fn %{post: updated_post, snapshot: snapshot} ->
        Post.changeset(updated_post, %{current_snapshot_id: snapshot.id})
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{set_current: post}} ->
          {:ok, Repo.preload(post, :current_snapshot)}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    end
  end

  def takedown_today_post(reason) do
    case get_today_post() do
      nil ->
        {:error, :not_found}

      post ->
        post
        |> Post.changeset(%{hidden: true, hidden_reason: reason})
        |> Repo.update()
    end
  end

  def takedown_post(post_id, reason) do
    case Repo.get(Post, post_id) do
      nil ->
        {:error, :not_found}

      post ->
        post
        |> Post.changeset(%{hidden: true, hidden_reason: reason})
        |> Repo.update()
    end
  end

  def restore_today_post do
    case get_today_post() do
      nil ->
        {:error, :not_found}

      post ->
        post
        |> Post.changeset(%{hidden: false, hidden_reason: nil})
        |> Repo.update()
    end
  end

  def list_highlights(snapshot_id) do
    Repo.all(
      from h in Highlight,
        where: h.post_snapshot_id == ^snapshot_id,
        order_by: [asc: h.start_g, asc: h.id],
        preload: [:comments]
    )
  end

  def create_highlight(snapshot, attrs) do
    selector = %{
      quote_exact: attrs["quote_exact"],
      quote_prefix: attrs["quote_prefix"],
      quote_suffix: attrs["quote_suffix"],
      start_g: attrs["start_g"],
      end_g: attrs["end_g"]
    }

    with {:ok, %{start_g: start_g, end_g: end_g}} <-
           TextAnchors.resolve(snapshot.normalized_text, selector),
         false <- overlap?(snapshot.id, start_g, end_g) do
      payload = %{
        post_snapshot_id: snapshot.id,
        session_id: attrs["session_id"],
        display_name: attrs["display_name"],
        color: attrs["color"],
        quote_exact: attrs["quote_exact"],
        quote_prefix: attrs["quote_prefix"],
        quote_suffix: attrs["quote_suffix"],
        start_g: start_g,
        end_g: end_g
      }

      %Highlight{}
      |> Highlight.changeset(payload)
      |> Repo.insert()
    else
      true -> {:error, :overlap}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_comment(highlight_id, attrs) do
    %Comment{}
    |> Comment.changeset(%{
      highlight_id: highlight_id,
      session_id: attrs["session_id"],
      display_name: attrs["display_name"],
      body: attrs["body"]
    })
    |> Repo.insert()
  end

  def soft_delete_comment(comment_id, session_id) do
    with %Comment{} = comment <- Repo.get(Comment, comment_id),
         true <- comment.session_id == session_id,
         true <- DateTime.diff(DateTime.utc_now(), comment.inserted_at, :minute) <= 5 do
      comment
      |> Comment.changeset(%{deleted_at: DateTime.utc_now(), body: "[deleted]"})
      |> Repo.update()
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
    end
  end

  def toggle_heart(post_id, session_id) do
    existing = Repo.get_by(PostHeart, post_id: post_id, session_id: session_id)

    case existing do
      nil ->
        %PostHeart{}
        |> PostHeart.changeset(%{post_id: post_id, session_id: session_id})
        |> Repo.insert()

      heart ->
        Repo.delete(heart)
    end
  end

  def heart_count(post_id) do
    Repo.aggregate(from(h in PostHeart, where: h.post_id == ^post_id), :count, :id)
  end

  def hearted_by?(post_id, session_id) do
    Repo.exists?(
      from h in PostHeart, where: h.post_id == ^post_id and h.session_id == ^session_id
    )
  end

  def create_report(post_id, attrs) do
    %Report{}
    |> Report.changeset(%{
      post_id: post_id,
      session_id: attrs["session_id"],
      display_name: attrs["display_name"],
      reason: attrs["reason"]
    })
    |> Repo.insert()
  end

  def list_reports do
    Repo.all(from r in Report, order_by: [desc: r.inserted_at], preload: [:post])
  end

  defp source_posts(opts) do
    case Keyword.fetch(opts, :source_posts) do
      {:ok, posts} when is_list(posts) -> {:ok, posts}
      {:ok, _} -> {:error, :invalid_source_posts}
      :error -> XTimeline.fetch_recent_posts(opts)
    end
  end

  defp upsert_source_post(source_post, session_id) do
    with {:ok, source} <- parse_source_post(source_post) do
      post =
        Repo.get_by(Post, tweet_id: source.tweet_id) ||
          Repo.get_by(Post, tweet_url: source.tweet_url) || %Post{}

      current_snapshot =
        if post.current_snapshot_id do
          Repo.get(PostSnapshot, post.current_snapshot_id)
        else
          nil
        end

      normalized_text = normalize_snapshot_text(source.snapshot_text)

      snapshot_changed? =
        is_nil(current_snapshot) or current_snapshot.normalized_text != normalized_text

      latest_version =
        if post.id do
          case latest_snapshot(post.id) do
            nil -> 0
            snapshot -> snapshot.version
          end
        else
          0
        end

      post_attrs = %{
        tweet_url: source.tweet_url,
        tweet_id: source.tweet_id,
        tweet_posted_at: source.posted_at,
        room_date: room_date_from_posted_at(source.posted_at)
      }

      Multi.new()
      |> Multi.insert_or_update(:post, Post.changeset(post, post_attrs))
      |> maybe_insert_snapshot(snapshot_changed?, latest_version, normalized_text, session_id)
      |> Repo.transaction()
      |> case do
        {:ok, %{set_current: updated_post}} ->
          {:ok, Repo.preload(updated_post, :current_snapshot)}

        {:ok, %{post: updated_post}} ->
          {:ok, Repo.preload(updated_post, :current_snapshot)}

        {:error, _step, reason, _changes_so_far} ->
          {:error, reason}
      end
    end
  end

  defp maybe_insert_snapshot(multi, false, _latest_version, _normalized_text, _session_id),
    do: multi

  defp maybe_insert_snapshot(multi, true, latest_version, normalized_text, session_id) do
    next_version = latest_version + 1

    multi
    |> Multi.insert(:snapshot, fn %{post: updated_post} ->
      PostSnapshot.changeset(%PostSnapshot{}, %{
        post_id: updated_post.id,
        version: next_version,
        normalized_text: normalized_text,
        submitted_by_session_id: session_id
      })
    end)
    |> Multi.update(:set_current, fn %{post: updated_post, snapshot: snapshot} ->
      Post.changeset(updated_post, %{current_snapshot_id: snapshot.id})
    end)
  end

  defp parse_source_post(source_post) when is_map(source_post) do
    tweet_id = source_value(source_post, :tweet_id)
    tweet_url = source_value(source_post, :tweet_url)
    snapshot_text = source_value(source_post, :snapshot_text)
    posted_at = source_value(source_post, :posted_at)

    cond do
      !is_binary(tweet_id) or String.trim(tweet_id) == "" ->
        {:error, :invalid_tweet_id}

      !is_binary(tweet_url) or String.trim(tweet_url) == "" ->
        {:error, :invalid_tweet_url}

      true ->
        {:ok,
         %{
           tweet_id: String.trim(tweet_id),
           tweet_url: String.trim(tweet_url),
           snapshot_text: snapshot_text,
           posted_at: normalize_source_posted_at(posted_at)
         }}
    end
  end

  defp parse_source_post(_), do: {:error, :invalid_source_post}

  defp source_value(source_post, key) do
    Map.get(source_post, key) || Map.get(source_post, Atom.to_string(key))
  end

  defp normalize_source_posted_at(%DateTime{} = posted_at), do: posted_at

  defp normalize_source_posted_at(posted_at) when is_binary(posted_at) do
    case DateTime.from_iso8601(posted_at) do
      {:ok, parsed, _offset} -> parsed
      _ -> nil
    end
  end

  defp normalize_source_posted_at(_), do: nil

  defp normalize_snapshot_text(snapshot_text) when is_binary(snapshot_text) do
    snapshot_text
    |> TextAnchors.normalize()
    |> case do
      "" -> "텍스트 본문이 없는 게시물입니다."
      normalized -> normalized
    end
  end

  defp normalize_snapshot_text(_), do: "텍스트 본문이 없는 게시물입니다."

  defp room_date_from_posted_at(%DateTime{} = posted_at), do: DateTime.to_date(posted_at)
  defp room_date_from_posted_at(_), do: today_date()

  defp overlap?(snapshot_id, start_g, end_g) do
    Repo.exists?(
      from h in Highlight,
        where:
          h.post_snapshot_id == ^snapshot_id and
            h.start_g < ^end_g and
            h.end_g > ^start_g
    )
  end

  defp extract_tweet_id(url) when is_binary(url) do
    case Regex.run(~r{/status/(\d+)}, url) do
      [_, id] -> id
      _ -> nil
    end
  end
end
