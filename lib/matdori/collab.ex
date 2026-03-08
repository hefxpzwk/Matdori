defmodule Matdori.Collab do
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Matdori.Embed
  alias Matdori.LinkPreview
  alias Matdori.Repo
  alias Matdori.TextAnchors
  alias Matdori.XTimeline

  alias Matdori.Collab.{
    Post,
    PostSnapshot,
    Highlight,
    Comment,
    PostHeart,
    PostView,
    Report,
    OverlayHighlight,
    UserProfile
  }

  @reaction_kinds ~w(like dislike)
  @overlay_highlight_limit 40

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
    case Repo.one(latest_post_query()) do
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

  def list_posts(limit \\ 20, opts \\ [])
      when is_integer(limit) and limit > 0 and is_list(opts) do
    sort = opts |> Keyword.get(:sort, "latest") |> normalize_list_sort()
    Repo.all(posts_query(limit, sort))
  end

  def get_profile_by_google_uid(google_uid) when is_binary(google_uid) do
    uid = normalize_google_uid(google_uid)

    if uid do
      case Repo.get_by(UserProfile, google_uid: uid) do
        nil ->
          %{display_name: nil, interests: [], color: nil}

        profile ->
          %{
            display_name: normalize_profile_display_name(profile.display_name),
            interests:
              normalize_interests(profile.interests || infer_interests(profile.interest)),
            color: normalize_profile_color(profile.color)
          }
      end
    else
      %{display_name: nil, interests: [], color: nil}
    end
  end

  def get_profile_by_google_uid(_google_uid), do: %{display_name: nil, interests: [], color: nil}

  def get_interest_by_google_uid(google_uid) do
    google_uid
    |> get_profile_by_google_uid()
    |> Map.get(:interests, [])
    |> Enum.join(", ")
  end

  def upsert_profile_by_google_uid(google_uid, attrs)
      when is_binary(google_uid) and is_map(attrs) do
    uid = normalize_google_uid(google_uid)

    if uid do
      cleaned_name = normalize_profile_display_name(attrs["display_name"] || attrs[:display_name])
      cleaned_interests = normalize_interests(attrs["interests"] || attrs[:interests])
      cleaned_color = normalize_profile_color(attrs["color"] || attrs[:color])
      fallback_interest = List.first(cleaned_interests) || ""

      profile = Repo.get_by(UserProfile, google_uid: uid) || %UserProfile{google_uid: uid}
      resolved_name = cleaned_name || normalize_profile_display_name(profile.display_name)
      resolved_color = cleaned_color || normalize_profile_color(profile.color) || "#3b82f6"

      Multi.new()
      |> Multi.insert_or_update(
        :profile,
        UserProfile.changeset(profile, %{
          google_uid: uid,
          display_name: resolved_name,
          color: resolved_color,
          interests: cleaned_interests,
          interest: fallback_interest
        })
      )
      |> Multi.run(:sync_display_names, fn _repo, _changes ->
        sync_display_name_for_google_uid(uid, resolved_name)
      end)
      |> Multi.run(:sync_colors, fn _repo, _changes ->
        sync_color_for_google_uid(uid, resolved_color)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{profile: saved_profile}} -> {:ok, saved_profile}
        {:error, :profile, reason, _changes} -> {:error, reason}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    else
      {:error, :invalid_google_uid}
    end
  end

  def upsert_profile_by_google_uid(_google_uid, _attrs), do: {:error, :invalid_google_uid}

  def upsert_interest_by_google_uid(google_uid, interest) when is_binary(google_uid) do
    interests = normalize_interests(interest)

    case upsert_profile_by_google_uid(google_uid, %{display_name: nil, interests: interests}) do
      {:ok, profile} -> {:ok, profile}
      {:error, reason} -> {:error, reason}
    end
  end

  def upsert_interest_by_google_uid(_google_uid, _interest), do: {:error, :invalid_google_uid}

  def list_created_posts_by_google_uid(google_uid, limit \\ 100)

  def list_created_posts_by_google_uid(google_uid, limit)
      when is_binary(google_uid) and is_integer(limit) and limit > 0 do
    uid = normalize_google_uid(google_uid)

    if uid do
      Repo.all(
        from p in Post,
          where: p.hidden == false and p.creator_google_uid == ^uid,
          order_by: [desc: p.inserted_at, desc: p.id],
          limit: ^limit
      )
    else
      []
    end
  end

  def list_created_posts_by_google_uid(_google_uid, _limit), do: []

  def list_liked_posts_by_google_uid(google_uid, limit \\ 100)

  def list_liked_posts_by_google_uid(google_uid, limit)
      when is_binary(google_uid) and is_integer(limit) and limit > 0 do
    uid = normalize_google_uid(google_uid)

    if uid do
      liked_posts_subquery =
        from h in PostHeart,
          where: h.google_uid == ^uid and h.kind == "like",
          group_by: h.post_id,
          select: %{post_id: h.post_id, latest_liked_at: max(h.inserted_at)}

      Repo.all(
        from p in Post,
          join: liked in subquery(liked_posts_subquery),
          on: liked.post_id == p.id,
          where: p.hidden == false,
          order_by: [desc: liked.latest_liked_at, desc: p.inserted_at, desc: p.id],
          limit: ^limit
      )
    else
      []
    end
  end

  def list_liked_posts_by_google_uid(_google_uid, _limit), do: []

  def list_highlighted_posts_by_google_uid(google_uid, limit \\ 100)

  def list_highlighted_posts_by_google_uid(google_uid, limit)
      when is_binary(google_uid) and is_integer(limit) and limit > 0 do
    list_highlighted_posts_for_user(google_uid, nil, limit)
  end

  def list_highlighted_posts_by_google_uid(_google_uid, _limit), do: []

  def list_highlighted_posts_for_user(google_uid, session_id, limit \\ 100)

  def list_highlighted_posts_for_user(google_uid, session_id, limit)
      when is_integer(limit) and limit > 0 do
    uid = normalize_google_uid(google_uid)
    sid = normalize_session_id(session_id)

    owner_dynamic = highlight_owner_dynamic(uid, sid)

    if owner_dynamic do
      text_highlighted_posts_subquery =
        from h in Highlight,
          join: s in PostSnapshot,
          on: s.id == h.post_snapshot_id,
          where: ^owner_dynamic,
          group_by: s.post_id,
          select: %{post_id: s.post_id, latest_highlighted_at: max(h.inserted_at)}

      overlay_highlighted_posts_subquery =
        from h in OverlayHighlight,
          where: ^owner_dynamic,
          group_by: h.post_id,
          select: %{post_id: h.post_id, latest_highlighted_at: max(h.inserted_at)}

      highlighted_posts_union_subquery =
        text_highlighted_posts_subquery
        |> union_all(^overlay_highlighted_posts_subquery)

      highlighted_posts_subquery =
        from u in subquery(highlighted_posts_union_subquery),
          group_by: u.post_id,
          select: %{post_id: u.post_id, latest_highlighted_at: max(u.latest_highlighted_at)}

      Repo.all(
        from p in Post,
          join: highlighted in subquery(highlighted_posts_subquery),
          on: highlighted.post_id == p.id,
          where: p.hidden == false,
          order_by: [desc: highlighted.latest_highlighted_at, desc: p.inserted_at, desc: p.id],
          limit: ^limit
      )
    else
      []
    end
  end

  def sync_configured_account_posts(opts \\ []) do
    with {:ok, source_posts} <- source_posts(opts) do
      session_id = opts[:session_id] || "x-sync"

      {posts, errors} =
        Enum.reduce(source_posts, {[], []}, fn source_post, {acc_posts, acc_errors} ->
          case upsert_source_post(source_post, session_id, nil) do
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

  def share_post(attrs, session_id) when is_map(attrs) and is_binary(session_id) do
    title = attrs["title"] || attrs[:title] || ""
    tweet_url = attrs["tweet_url"] || attrs[:tweet_url] || ""
    snapshot_text = attrs["snapshot_text"] || attrs[:snapshot_text]
    google_uid = attrs["google_uid"] || attrs[:google_uid]

    with {:ok, normalized_title} <- normalize_share_title(title),
         {:ok, normalized_url, tweet_id} <- normalize_share_tweet_url(tweet_url),
         preview_attrs <- maybe_fetch_link_preview(normalized_url),
         {:ok, post} <-
           upsert_source_post(
             Map.merge(
               %{
                 title: normalized_title,
                 tweet_id: tweet_id,
                 tweet_url: normalized_url,
                 snapshot_text: normalize_share_snapshot_text(snapshot_text, normalized_title),
                 posted_at: DateTime.utc_now()
               },
               preview_attrs
             ),
             session_id,
             google_uid
           ) do
      {:ok, post}
    end
  end

  def find_post_by_url(url) when is_binary(url) do
    with {:ok, normalized_url, _tweet_id} <- normalize_share_tweet_url(url) do
      case Repo.get_by(Post, tweet_url: normalized_url, hidden: false) do
        nil -> :not_found
        post -> {:ok, Repo.preload(post, :current_snapshot)}
      end
    end
  end

  def find_post_by_url(_), do: {:error, :invalid_tweet_url}

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

  def delete_post_by_owner(post_id, google_uid)
      when is_integer(post_id) and is_binary(google_uid) do
    uid = normalize_google_uid(google_uid)

    if uid do
      case Repo.get(Post, post_id) do
        nil ->
          {:error, :not_found}

        %Post{} = post ->
          if post.creator_google_uid == uid do
            post
            |> Post.changeset(%{hidden: true, hidden_reason: "deleted_by_owner"})
            |> Repo.update()
          else
            {:error, :forbidden}
          end
      end
    else
      {:error, :invalid_google_uid}
    end
  end

  def delete_post_by_owner(_post_id, _google_uid), do: {:error, :invalid_google_uid}

  def delete_highlights_for_user_in_post(post_id, google_uid, session_id \\ nil)

  def delete_highlights_for_user_in_post(post_id, google_uid, session_id)
      when is_integer(post_id) do
    uid = normalize_google_uid(google_uid)
    sid = normalize_session_id(session_id)

    {deleted_text, deleted_overlay} =
      cond do
        is_binary(uid) and is_binary(sid) ->
          text_deleted =
            Repo.delete_all(
              from h in Highlight,
                join: s in PostSnapshot,
                on: s.id == h.post_snapshot_id,
                where:
                  s.post_id == ^post_id and
                    (h.google_uid == ^uid or (is_nil(h.google_uid) and h.session_id == ^sid))
            )

          overlay_deleted =
            Repo.delete_all(
              from h in OverlayHighlight,
                where:
                  h.post_id == ^post_id and
                    (h.google_uid == ^uid or (is_nil(h.google_uid) and h.session_id == ^sid))
            )

          {elem(text_deleted, 0), elem(overlay_deleted, 0)}

        is_binary(uid) ->
          text_deleted =
            Repo.delete_all(
              from h in Highlight,
                join: s in PostSnapshot,
                on: s.id == h.post_snapshot_id,
                where: s.post_id == ^post_id and h.google_uid == ^uid
            )

          overlay_deleted =
            Repo.delete_all(
              from h in OverlayHighlight,
                where: h.post_id == ^post_id and h.google_uid == ^uid
            )

          {elem(text_deleted, 0), elem(overlay_deleted, 0)}

        is_binary(sid) ->
          text_deleted =
            Repo.delete_all(
              from h in Highlight,
                join: s in PostSnapshot,
                on: s.id == h.post_snapshot_id,
                where: s.post_id == ^post_id and h.session_id == ^sid
            )

          overlay_deleted =
            Repo.delete_all(
              from h in OverlayHighlight,
                where: h.post_id == ^post_id and h.session_id == ^sid
            )

          {elem(text_deleted, 0), elem(overlay_deleted, 0)}

        true ->
          {-1, -1}
      end

    if deleted_text >= 0 and deleted_overlay >= 0 do
      {:ok,
       %{
         deleted_text: deleted_text,
         deleted_overlay: deleted_overlay,
         deleted_total: deleted_text + deleted_overlay
       }}
    else
      {:error, :invalid_owner}
    end
  end

  def delete_highlights_for_user_in_post(_post_id, _google_uid, _session_id),
    do: {:error, :invalid_owner}

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

  def list_overlay_highlights(post_id) when is_integer(post_id) do
    Repo.all(
      from h in OverlayHighlight,
        where: h.post_id == ^post_id,
        order_by: [asc: h.inserted_at, asc: h.id]
    )
  end

  def list_overlay_highlights(_post_id), do: []

  def replace_overlay_highlights(post_id, attrs)
      when is_integer(post_id) and is_map(attrs) do
    session_id = attrs["session_id"] || attrs[:session_id]
    google_uid = attrs["google_uid"] || attrs[:google_uid]
    display_name = attrs["display_name"] || attrs[:display_name]
    color = attrs["color"] || attrs[:color]
    highlights = attrs["highlights"] || attrs[:highlights] || []

    with true <- is_binary(session_id) and session_id != "",
         true <- is_binary(display_name) and String.trim(display_name) != "",
         true <- is_binary(color) and color != "" do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      normalized_rows =
        highlights
        |> normalize_overlay_highlights_payload()
        |> Enum.map(fn zone ->
          %{
            post_id: post_id,
            highlight_key: zone.highlight_key,
            session_id: String.slice(session_id, 0, 100),
            google_uid: normalize_google_uid(google_uid),
            display_name: normalize_overlay_display_name(display_name),
            color: normalize_overlay_color(color),
            left: zone.left,
            top: zone.top,
            width: zone.width,
            height: zone.height,
            comment: zone.comment,
            inserted_at: now,
            updated_at: now
          }
        end)

      Multi.new()
      |> Multi.delete_all(
        :delete_existing,
        from(h in OverlayHighlight, where: h.post_id == ^post_id and h.session_id == ^session_id)
      )
      |> maybe_insert_overlay_highlights(normalized_rows)
      |> Repo.transaction()
      |> case do
        {:ok, _} -> {:ok, list_overlay_highlights(post_id)}
        {:error, _step, reason, _} -> {:error, reason}
      end
    else
      _ -> {:error, :invalid_overlay_highlights}
    end
  end

  def replace_overlay_highlights(_post_id, _attrs), do: {:error, :invalid_overlay_highlights}

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
        google_uid: attrs["google_uid"],
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
      google_uid: normalize_google_uid(attrs["google_uid"]),
      display_name: attrs["display_name"],
      color: normalize_overlay_color(attrs["color"] || attrs[:color]),
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

  def toggle_reaction(post_id, session_id, kind) when kind in @reaction_kinds,
    do: toggle_reaction(post_id, session_id, kind, nil)

  def toggle_reaction(_post_id, _session_id, _kind), do: {:error, :invalid_reaction_kind}

  def toggle_reaction(post_id, session_id, kind, google_uid) when kind in @reaction_kinds do
    existing = Repo.get_by(PostHeart, post_id: post_id, session_id: session_id)

    case existing do
      nil ->
        %PostHeart{}
        |> PostHeart.changeset(%{
          post_id: post_id,
          session_id: session_id,
          google_uid: normalize_google_uid(google_uid),
          kind: kind
        })
        |> Repo.insert()

      %PostHeart{kind: ^kind} = heart ->
        Repo.delete(heart)

      heart ->
        heart
        |> PostHeart.changeset(%{kind: kind, google_uid: normalize_google_uid(google_uid)})
        |> Repo.update()
    end
  end

  def toggle_reaction(_post_id, _session_id, _kind, _google_uid),
    do: {:error, :invalid_reaction_kind}

  def toggle_heart(post_id, session_id), do: toggle_reaction(post_id, session_id, "like")

  def reaction_count(post_id, kind) when kind in @reaction_kinds do
    Repo.aggregate(
      from(h in PostHeart, where: h.post_id == ^post_id and h.kind == ^kind),
      :count,
      :id
    )
  end

  def reaction_count(_post_id, _kind), do: 0

  def heart_count(post_id), do: reaction_count(post_id, "like")

  def reacted_by?(post_id, session_id, kind) when kind in @reaction_kinds do
    Repo.exists?(
      from h in PostHeart,
        where: h.post_id == ^post_id and h.session_id == ^session_id and h.kind == ^kind
    )
  end

  def reacted_by?(_post_id, _session_id, _kind), do: false

  def hearted_by?(post_id, session_id), do: reacted_by?(post_id, session_id, "like")

  def register_view(post_id, session_id) when is_integer(post_id) and is_binary(session_id) do
    _ = register_view_with_status(post_id, session_id)
    :ok
  end

  def register_view(_post_id, _session_id), do: :ok

  def register_view_with_status(post_id, session_id)
      when is_integer(post_id) and is_binary(session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    {inserted_rows, _} =
      Repo.insert_all(
        PostView,
        [%{post_id: post_id, session_id: session_id, inserted_at: now}],
        on_conflict: :nothing,
        conflict_target: [:post_id, :session_id]
      )

    if inserted_rows == 1, do: :inserted, else: :existing
  end

  def register_view_with_status(_post_id, _session_id), do: :ignored

  def view_count(post_id) when is_integer(post_id) do
    Repo.aggregate(from(v in PostView, where: v.post_id == ^post_id), :count, :id)
  end

  def view_count(_post_id), do: 0

  def create_report(post_id, attrs) do
    %Report{}
    |> Report.changeset(%{
      post_id: post_id,
      session_id: attrs["session_id"],
      google_uid: normalize_google_uid(attrs["google_uid"]),
      display_name: attrs["display_name"],
      reason: attrs["reason"]
    })
    |> Repo.insert()
  end

  defp sync_display_name_for_google_uid(_google_uid, nil), do: {:ok, :skipped}

  defp sync_display_name_for_google_uid(google_uid, display_name) do
    Repo.update_all(
      from(h in Highlight, where: h.google_uid == ^google_uid),
      set: [display_name: display_name]
    )

    Repo.update_all(
      from(h in OverlayHighlight, where: h.google_uid == ^google_uid),
      set: [display_name: display_name]
    )

    Repo.update_all(
      from(c in Comment, where: c.google_uid == ^google_uid),
      set: [display_name: display_name]
    )

    Repo.update_all(
      from(r in Report, where: r.google_uid == ^google_uid),
      set: [display_name: display_name]
    )

    {:ok, :synced}
  end

  defp sync_color_for_google_uid(_google_uid, nil), do: {:ok, :skipped}

  defp sync_color_for_google_uid(google_uid, color) do
    Repo.update_all(
      from(h in Highlight, where: h.google_uid == ^google_uid),
      set: [color: color]
    )

    Repo.update_all(
      from(h in OverlayHighlight, where: h.google_uid == ^google_uid),
      set: [color: color]
    )

    Repo.update_all(
      from(c in Comment, where: c.google_uid == ^google_uid),
      set: [color: color]
    )

    {:ok, :synced}
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

  defp upsert_source_post(source_post, session_id, google_uid) do
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
        tweet_id: source.tweet_id
      }

      post_attrs =
        if is_nil(post.creator_google_uid) do
          case normalize_google_uid(google_uid) do
            nil -> post_attrs
            uid -> Map.put(post_attrs, :creator_google_uid, uid)
          end
        else
          post_attrs
        end

      post_attrs =
        if is_binary(source.title) and source.title != "" do
          if is_binary(post.title) and String.trim(post.title) != "" do
            post_attrs
          else
            Map.put(post_attrs, :title, source.title)
          end
        else
          post_attrs
        end

      post_attrs = maybe_put_when_blank(post_attrs, post, :preview_title, source.preview_title)

      post_attrs =
        maybe_put_when_blank(post_attrs, post, :preview_description, source.preview_description)

      post_attrs =
        maybe_put_when_blank(post_attrs, post, :preview_image_url, source.preview_image_url)

      post_attrs =
        if is_nil(post.tweet_posted_at) and source.posted_at do
          post_attrs
          |> Map.put(:tweet_posted_at, source.posted_at)
          |> Map.put(:room_date, room_date_from_posted_at(source.posted_at))
        else
          post_attrs
        end

      post_attrs =
        if is_nil(post.room_date) do
          Map.put(post_attrs, :room_date, room_date_from_posted_at(source.posted_at))
        else
          post_attrs
        end

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

  defp maybe_insert_overlay_highlights(multi, []), do: multi

  defp maybe_insert_overlay_highlights(multi, rows) do
    Multi.insert_all(multi, :insert_overlay_highlights, OverlayHighlight, rows)
  end

  defp normalize_overlay_highlights_payload(value) when is_list(value) do
    value
    |> Enum.reduce([], fn zone, acc ->
      case normalize_overlay_highlight_payload(zone) do
        nil -> acc
        normalized -> [normalized | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.take(@overlay_highlight_limit)
  end

  defp normalize_overlay_highlights_payload(_value), do: []

  defp normalize_overlay_highlight_payload(zone) when is_map(zone) do
    with {:ok, left} <- normalize_overlay_ratio(Map.get(zone, :left) || Map.get(zone, "left")),
         {:ok, top} <- normalize_overlay_ratio(Map.get(zone, :top) || Map.get(zone, "top")),
         {:ok, width} <- normalize_overlay_ratio(Map.get(zone, :width) || Map.get(zone, "width")),
         {:ok, height} <-
           normalize_overlay_ratio(Map.get(zone, :height) || Map.get(zone, "height")) do
      max_width = max(1.0 - left, 0.0)
      max_height = max(1.0 - top, 0.0)
      safe_width = min(width, max_width)
      safe_height = min(height, max_height)

      if safe_width > 0.0 and safe_height > 0.0 do
        %{
          highlight_key:
            normalize_overlay_highlight_key(
              Map.get(zone, :id) || Map.get(zone, "id"),
              left,
              top,
              safe_width,
              safe_height
            ),
          left: left,
          top: top,
          width: safe_width,
          height: safe_height,
          comment: normalize_overlay_comment(Map.get(zone, :comment) || Map.get(zone, "comment"))
        }
      else
        nil
      end
    else
      :error -> nil
    end
  end

  defp normalize_overlay_highlight_payload(_zone), do: nil

  defp normalize_overlay_ratio(value) when is_integer(value),
    do: {:ok, clamp_overlay_ratio(value * 1.0)}

  defp normalize_overlay_ratio(value) when is_float(value), do: {:ok, clamp_overlay_ratio(value)}

  defp normalize_overlay_ratio(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, clamp_overlay_ratio(parsed)}
      _ -> :error
    end
  end

  defp normalize_overlay_ratio(_value), do: :error

  defp clamp_overlay_ratio(value) do
    rounded = Float.round(value, 4)

    cond do
      rounded < 0.0 -> 0.0
      rounded > 1.0 -> 1.0
      true -> rounded
    end
  end

  defp normalize_overlay_highlight_key(value, left, top, width, height) when is_binary(value) do
    case value |> String.trim() |> String.slice(0, 80) do
      "" -> normalize_overlay_highlight_key(nil, left, top, width, height)
      key -> key
    end
  end

  defp normalize_overlay_highlight_key(_value, left, top, width, height) do
    hash =
      :crypto.hash(:sha256, "#{left}:#{top}:#{width}:#{height}")
      |> Base.encode16(case: :lower)

    "hl-" <> String.slice(hash, 0, 16)
  end

  defp normalize_overlay_display_name(name) do
    name
    |> String.trim()
    |> String.slice(0, 30)
  end

  defp normalize_overlay_comment(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.slice(0, 240)
  end

  defp normalize_overlay_comment(_value), do: ""

  defp normalize_overlay_color(value) do
    if is_binary(value) and Regex.match?(~r/^#[0-9a-fA-F]{6}$/, value) do
      value
    else
      "#3b82f6"
    end
  end

  defp parse_source_post(source_post) when is_map(source_post) do
    tweet_id = source_value(source_post, :tweet_id)
    tweet_url = source_value(source_post, :tweet_url)
    title = source_value(source_post, :title)
    preview_title = source_value(source_post, :preview_title)
    preview_description = source_value(source_post, :preview_description)
    preview_image_url = source_value(source_post, :preview_image_url)
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
           title: normalize_source_title(title),
           preview_title: normalize_preview_text(preview_title, 120),
           preview_description: normalize_preview_text(preview_description, 220),
           preview_image_url: normalize_preview_image_url(preview_image_url),
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

  defp normalize_source_title(title) when is_binary(title) do
    case String.trim(title) do
      "" -> nil
      cleaned -> String.slice(cleaned, 0, 120)
    end
  end

  defp normalize_source_title(_), do: nil

  defp normalize_preview_text(value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      cleaned -> String.slice(cleaned, 0, max)
    end
  end

  defp normalize_preview_text(_value, _max), do: nil

  defp normalize_preview_image_url(url) when is_binary(url) do
    case URI.parse(String.trim(url)) do
      %URI{scheme: scheme, host: host} = parsed
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        URI.to_string(parsed)

      _ ->
        nil
    end
  end

  defp normalize_preview_image_url(_), do: nil

  defp normalize_snapshot_text(snapshot_text) when is_binary(snapshot_text) do
    snapshot_text
    |> TextAnchors.normalize()
    |> case do
      "" -> "텍스트 본문이 없는 게시물입니다."
      normalized -> normalized
    end
  end

  defp normalize_snapshot_text(_), do: "텍스트 본문이 없는 게시물입니다."

  defp normalize_share_title(title) when is_binary(title) do
    case String.trim(title) do
      "" -> {:error, :invalid_title}
      cleaned -> {:ok, String.slice(cleaned, 0, 120)}
    end
  end

  defp normalize_share_title(_), do: {:error, :invalid_title}

  defp normalize_share_snapshot_text(snapshot_text, _title) when is_binary(snapshot_text) do
    case String.trim(snapshot_text) do
      "" -> nil
      text -> text
    end
  end

  defp normalize_share_snapshot_text(_snapshot_text, _title), do: nil

  defp maybe_fetch_link_preview(url) do
    case Embed.classify(url).mode do
      :native_embed -> %{}
      :preview_only -> LinkPreview.fetch(url)
    end
  end

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

  defp latest_post_query do
    from p in Post,
      where: p.hidden == false,
      order_by: [
        desc: fragment("COALESCE(?, ?)", p.tweet_posted_at, p.inserted_at),
        desc: p.id
      ],
      limit: 1
  end

  defp posts_query(limit, sort) do
    from p in Post,
      left_join: like_counts in subquery(reaction_counts_subquery("like")),
      on: like_counts.post_id == p.id,
      left_join: dislike_counts in subquery(reaction_counts_subquery("dislike")),
      on: dislike_counts.post_id == p.id,
      left_join: view_counts in subquery(view_counts_subquery()),
      on: view_counts.post_id == p.id,
      where: p.hidden == false,
      order_by: ^list_sort_order(sort),
      limit: ^limit,
      select_merge: %{
        like_count: coalesce(like_counts.reaction_count, 0),
        dislike_count: coalesce(dislike_counts.reaction_count, 0),
        view_count: coalesce(view_counts.view_count, 0)
      }
  end

  defp reaction_counts_subquery(kind) when kind in @reaction_kinds do
    from h in PostHeart,
      where: h.kind == ^kind,
      group_by: h.post_id,
      select: %{post_id: h.post_id, reaction_count: count(h.id)}
  end

  defp view_counts_subquery do
    from v in PostView,
      group_by: v.post_id,
      select: %{post_id: v.post_id, view_count: count(v.id)}
  end

  defp normalize_list_sort(sort) when sort in ["latest", "likes", "views"], do: sort
  defp normalize_list_sort(_sort), do: "latest"

  defp list_sort_order("likes") do
    [
      desc:
        dynamic(
          [_p, like_counts, _dislike_counts, _view_counts],
          coalesce(like_counts.reaction_count, 0)
        ),
      desc: dynamic([p], p.inserted_at),
      desc: dynamic([p], p.id)
    ]
  end

  defp list_sort_order("views") do
    [
      desc:
        dynamic(
          [_p, _like_counts, _dislike_counts, view_counts],
          coalesce(view_counts.view_count, 0)
        ),
      desc: dynamic([p], p.inserted_at),
      desc: dynamic([p], p.id)
    ]
  end

  defp list_sort_order(_sort) do
    [
      desc: dynamic([p], p.inserted_at),
      desc: dynamic([p], p.id)
    ]
  end

  defp normalize_google_uid(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      uid -> String.slice(uid, 0, 200)
    end
  end

  defp normalize_google_uid(_value), do: nil

  defp normalize_session_id(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      session_id -> String.slice(session_id, 0, 100)
    end
  end

  defp normalize_session_id(_value), do: nil

  defp normalize_interest(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.slice(0, 160)
  end

  defp normalize_interest(_value), do: ""

  defp normalize_profile_display_name(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 30)
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  defp normalize_profile_display_name(_value), do: nil

  defp normalize_profile_color(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(~r/^#[0-9a-fA-F]{6}$/, trimmed) do
      String.downcase(trimmed)
    else
      nil
    end
  end

  defp normalize_profile_color(_value), do: nil

  defp normalize_interests(value) when is_binary(value) do
    value
    |> String.split([",", "\n", "|"], trim: true)
    |> normalize_interests()
  end

  defp normalize_interests(values) when is_list(values) do
    values
    |> Enum.map(&normalize_interest/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.uniq()
    |> Enum.take(12)
  end

  defp normalize_interests(_), do: []

  defp infer_interests(value) when is_binary(value) and value != "",
    do: [normalize_interest(value)]

  defp infer_interests(_), do: []

  defp highlight_owner_dynamic(uid, sid) when is_binary(uid) and is_binary(sid) do
    dynamic([h], h.google_uid == ^uid or (is_nil(h.google_uid) and h.session_id == ^sid))
  end

  defp highlight_owner_dynamic(uid, _sid) when is_binary(uid) do
    dynamic([h], h.google_uid == ^uid)
  end

  defp highlight_owner_dynamic(nil, sid) when is_binary(sid) do
    dynamic([h], h.session_id == ^sid)
  end

  defp highlight_owner_dynamic(_uid, _sid), do: nil

  defp normalize_share_tweet_url(url) when is_binary(url) do
    trimmed = String.trim(url)

    with %URI{scheme: scheme, host: host, path: path} = uri <- URI.parse(trimmed),
         true <- valid_http_url?(scheme, host) do
      if host in ["x.com", "www.x.com", "twitter.com", "www.twitter.com"] do
        case Regex.run(~r{^/([^/?#]+)/status/(\d+)}, path || "") do
          [_, username, tweet_id] ->
            {:ok, "https://x.com/#{username}/status/#{tweet_id}", tweet_id}

          _ ->
            normalized_url = normalize_generic_url(uri)
            generated_id = generic_tweet_id(normalized_url)
            {:ok, normalized_url, generated_id}
        end
      else
        normalized_url = normalize_generic_url(uri)
        generated_id = generic_tweet_id(normalized_url)
        {:ok, normalized_url, generated_id}
      end
    else
      _ -> {:error, :invalid_tweet_url}
    end
  end

  defp normalize_share_tweet_url(_), do: {:error, :invalid_tweet_url}

  defp valid_http_url?(scheme, host) do
    scheme in ["http", "https"] and is_binary(host) and String.trim(host) != ""
  end

  defp normalize_generic_url(%URI{} = uri) do
    uri
    |> Map.put(:fragment, nil)
    |> URI.to_string()
  end

  defp generic_tweet_id(url) do
    hash = :crypto.hash(:sha256, url) |> Base.encode16(case: :lower)
    "url-" <> String.slice(hash, 0, 32)
  end

  defp maybe_put_when_blank(attrs, post, key, value) when is_binary(value) and value != "" do
    existing = Map.get(post, key)

    if is_binary(existing) and String.trim(existing) != "" do
      attrs
    else
      Map.put(attrs, key, value)
    end
  end

  defp maybe_put_when_blank(attrs, _post, _key, _value), do: attrs
end
