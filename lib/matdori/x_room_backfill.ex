defmodule Matdori.XRoomBackfill do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Matdori.Collab
  alias Matdori.Collab.Post
  alias Matdori.Repo
  alias Matdori.XSyncState
  alias Matdori.XTimeline

  @default_max_posts 1_000
  @default_batch_size 100

  def run(opts \\ []) do
    with {:ok, parsed} <- parse_opts(opts),
         {:ok, username} <- resolve_username(parsed) do
      with_backfill_lock(username, fn ->
        state = load_state(username)

        if parsed.resume and state.backfill_completed_at && is_nil(state.backfill_next_token) do
          {:ok, completed_summary(parsed, username)}
        else
          start_token = if parsed.resume, do: state.backfill_next_token, else: nil

          do_run(
            parsed,
            username,
            start_token,
            parsed.source_pages,
            0,
            0,
            0,
            0,
            0
          )
        end
      end)
    end
  end

  defp do_run(
         opts,
         username,
         token,
         source_pages,
         pages,
         scanned,
         processed,
         planned,
         inserted_or_updated
       ) do
    remaining = opts.max_posts - processed

    cond do
      remaining <= 0 ->
        summary(
          username,
          opts,
          pages,
          scanned,
          processed,
          planned,
          inserted_or_updated,
          token,
          false
        )

      true ->
        page_size = min(opts.batch_size, remaining)

        case fetch_page(username, token, page_size, source_pages) do
          {:ok, %{posts: posts, next_token: next_token}, remaining_source_pages} ->
            bounded_posts = Enum.take(posts, remaining)
            scanned_next = scanned + length(bounded_posts)

            case apply_page(opts, bounded_posts, planned, inserted_or_updated) do
              {:ok, page_planned, page_inserted} ->
                processed_next = processed + length(bounded_posts)

                if opts.sleep_ms > 0 and is_binary(next_token) do
                  Process.sleep(opts.sleep_ms)
                end

                cond do
                  bounded_posts == [] and is_binary(next_token) and next_token == token ->
                    {:error, :stalled_pagination}

                  is_nil(next_token) ->
                    case maybe_mark_state(username, opts, nil, DateTime.utc_now()) do
                      :ok ->
                        summary(
                          username,
                          opts,
                          pages + 1,
                          scanned_next,
                          processed_next,
                          page_planned,
                          page_inserted,
                          nil,
                          true
                        )

                      {:error, reason} ->
                        {:error, reason}
                    end

                  true ->
                    case maybe_mark_state(username, opts, next_token, nil) do
                      :ok ->
                        do_run(
                          opts,
                          username,
                          next_token,
                          remaining_source_pages,
                          pages + 1,
                          scanned_next,
                          processed_next,
                          page_planned,
                          page_inserted
                        )

                      {:error, reason} ->
                        {:error, reason}
                    end
                end

              {:error, reason} ->
                {:error, {:backfill_page_failed, reason}}
            end

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_page(_username, _token, _page_size, source_pages) when is_list(source_pages) do
    case source_pages do
      [first | rest] ->
        {:ok,
         %{
           posts: Map.get(first, :posts, Map.get(first, "posts", [])),
           next_token: Map.get(first, :next_token, Map.get(first, "next_token"))
         }, rest}

      [] ->
        {:ok, %{posts: [], next_token: nil}, []}
    end
  end

  defp fetch_page(username, token, page_size, _source_pages) do
    case XTimeline.fetch_recent_posts_page(
           username: username,
           max_results: page_size,
           pagination_token: token
         ) do
      {:ok, %{posts: posts, next_token: next_token}} ->
        {:ok, %{posts: posts, next_token: next_token}, nil}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp apply_page(opts, posts, planned, inserted_or_updated) do
    cond do
      opts.dry_run ->
        page_planned = planned + estimate_new_posts(posts)
        {:ok, page_planned, inserted_or_updated}

      posts == [] ->
        {:ok, planned, inserted_or_updated}

      true ->
        case Collab.sync_configured_account_posts(
               source_posts: posts,
               session_id: opts.session_id
             ) do
          {:ok, %{inserted_or_updated: count}} ->
            {:ok, planned + count, inserted_or_updated + count}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp estimate_new_posts([]), do: 0

  defp estimate_new_posts(posts) do
    tweet_ids = Enum.map(posts, & &1.tweet_id)

    existing_ids =
      Repo.all(from p in Post, where: p.tweet_id in ^tweet_ids, select: p.tweet_id)
      |> MapSet.new()

    Enum.count(tweet_ids, fn tweet_id -> !MapSet.member?(existing_ids, tweet_id) end)
  end

  defp parse_opts(opts) do
    parsed = %{
      dry_run: Keyword.get(opts, :dry_run, false) == true,
      resume: Keyword.get(opts, :resume, false) == true,
      max_posts: Keyword.get(opts, :max_posts, @default_max_posts),
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      sleep_ms: Keyword.get(opts, :sleep_ms, 0),
      session_id: Keyword.get(opts, :session_id, "x-backfill"),
      username: Keyword.get(opts, :username),
      source_pages: Keyword.get(opts, :source_pages)
    }

    cond do
      !is_integer(parsed.max_posts) or parsed.max_posts <= 0 ->
        {:error, :invalid_max_posts}

      !is_integer(parsed.batch_size) or parsed.batch_size <= 0 ->
        {:error, :invalid_batch_size}

      !is_integer(parsed.sleep_ms) or parsed.sleep_ms < 0 ->
        {:error, :invalid_sleep_ms}

      !is_nil(parsed.source_pages) and !is_list(parsed.source_pages) ->
        {:error, :invalid_source_pages}

      true ->
        {:ok, parsed}
    end
  end

  defp resolve_username(%{username: username}) when is_binary(username) and username != "",
    do: {:ok, username}

  defp resolve_username(_opts) do
    case Application.get_env(:matdori, :x_source_username) do
      username when is_binary(username) and username != "" -> {:ok, username}
      _ -> {:error, :missing_x_source_username}
    end
  end

  defp load_state(username) do
    Repo.get_by(XSyncState, source_username: username) ||
      %XSyncState{source_username: username, backfill_next_token: nil, backfill_completed_at: nil}
  end

  defp maybe_mark_state(_username, %{resume: false}, _token, _completed_at), do: :ok
  defp maybe_mark_state(_username, %{dry_run: true}, _token, _completed_at), do: :ok

  defp maybe_mark_state(username, _opts, token, completed_at) do
    state =
      Repo.get_by(XSyncState, source_username: username) || %XSyncState{source_username: username}

    attrs = %{backfill_next_token: token, backfill_completed_at: completed_at}

    state
    |> XSyncState.changeset(attrs)
    |> Repo.insert_or_update()
    |> case do
      {:ok, _state} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp completed_summary(opts, username) do
    %{
      dry_run: opts.dry_run,
      resume: opts.resume,
      source_username: username,
      pages: 0,
      scanned_posts: 0,
      processed_posts: 0,
      planned_upserts: 0,
      inserted_or_updated: 0,
      next_token: nil,
      completed: true
    }
  end

  defp summary(
         username,
         opts,
         pages,
         scanned,
         processed,
         planned,
         inserted_or_updated,
         next_token,
         completed
       ) do
    {:ok,
     %{
       dry_run: opts.dry_run,
       resume: opts.resume,
       source_username: username,
       pages: pages,
       scanned_posts: scanned,
       processed_posts: processed,
       planned_upserts: planned,
       inserted_or_updated: inserted_or_updated,
       next_token: next_token,
       completed: completed
     }}
  end

  defp with_backfill_lock(username, fun) do
    case :global.trans({__MODULE__, username}, fn -> fun.() end, [node()]) do
      :aborted -> {:error, :backfill_lock_held}
      result -> result
    end
  end
end
