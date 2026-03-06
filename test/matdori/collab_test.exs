defmodule Matdori.CollabTest do
  use Matdori.DataCase, async: false

  alias Matdori.Collab
  alias Matdori.Collab.{Post, PostSnapshot}

  test "toggle_heart/2 toggles and enforces one heart per session" do
    post = insert_post_with_snapshot()

    assert {:ok, _} = Collab.toggle_heart(post.id, "session-1")
    assert Collab.heart_count(post.id) == 1

    assert {:ok, _} = Collab.toggle_heart(post.id, "session-1")
    assert Collab.heart_count(post.id) == 0
  end

  test "create_highlight/2 rejects overlaps" do
    post = insert_post_with_snapshot()
    snapshot = Repo.preload(post, :current_snapshot).current_snapshot

    attrs = %{
      "session_id" => "session-1",
      "display_name" => "Tester",
      "color" => "#111111",
      "quote_exact" => "Hello",
      "quote_prefix" => nil,
      "quote_suffix" => " world",
      "start_g" => 0,
      "end_g" => 5
    }

    assert {:ok, _} = Collab.create_highlight(snapshot, attrs)

    overlapping = Map.merge(attrs, %{"quote_exact" => "llo wo", "start_g" => 2, "end_g" => 8})
    assert {:error, :overlap} = Collab.create_highlight(snapshot, overlapping)
  end

  test "sync_configured_account_posts/1 imports posts and latest order follows tweet_posted_at" do
    older = System.unique_integer([:positive])
    newer = System.unique_integer([:positive])

    assert {:ok, %{inserted_or_updated: 2, errors: []}} =
             Collab.sync_configured_account_posts(
               source_posts: [
                 %{
                   tweet_id: Integer.to_string(older),
                   tweet_url: "https://x.com/bbiribarabu/status/#{older}",
                   snapshot_text: "older post",
                   posted_at: ~U[2026-03-06 09:00:00Z]
                 },
                 %{
                   tweet_id: Integer.to_string(newer),
                   tweet_url: "https://x.com/bbiribarabu/status/#{newer}",
                   snapshot_text: "newer post",
                   posted_at: ~U[2026-03-06 10:00:00Z]
                 }
               ],
               session_id: "sync-order"
             )

    latest = Collab.get_latest_post_with_versions()
    assert latest.tweet_id == Integer.to_string(newer)

    [first | _] = Collab.list_posts(2)
    assert first.tweet_id == Integer.to_string(newer)
  end

  test "sync_configured_account_posts/1 creates new snapshot version when source text changes" do
    tweet = System.unique_integer([:positive])
    tweet_id = Integer.to_string(tweet)
    tweet_url = "https://x.com/bbiribarabu/status/#{tweet_id}"

    assert {:ok, %{inserted_or_updated: 1, errors: []}} =
             Collab.sync_configured_account_posts(
               source_posts: [
                 %{
                   tweet_id: tweet_id,
                   tweet_url: tweet_url,
                   snapshot_text: "첫 번째 본문",
                   posted_at: ~U[2026-03-06 11:00:00Z]
                 }
               ],
               session_id: "sync-version"
             )

    assert {:ok, %{inserted_or_updated: 1, errors: []}} =
             Collab.sync_configured_account_posts(
               source_posts: [
                 %{
                   tweet_id: tweet_id,
                   tweet_url: tweet_url,
                   snapshot_text: "두 번째 본문",
                   posted_at: ~U[2026-03-06 11:00:00Z]
                 }
               ],
               session_id: "sync-version"
             )

    post =
      Post
      |> where([p], p.tweet_id == ^tweet_id)
      |> Repo.one!()
      |> Repo.preload([
        :current_snapshot,
        snapshots: from(s in PostSnapshot, order_by: [desc: s.version])
      ])

    assert post.current_snapshot.version == 2
    assert post.current_snapshot.normalized_text == "두 번째 본문"
    assert Enum.map(post.snapshots, & &1.version) == [2, 1]
  end

  defp insert_post_with_snapshot do
    unique = System.unique_integer([:positive])

    {:ok, post} =
      %Post{}
      |> Post.changeset(%{
        tweet_url: "https://x.com/user/status/#{unique}",
        tweet_id: Integer.to_string(unique),
        room_date: Date.add(~D[2026-03-05], rem(unique, 20)),
        hidden: false
      })
      |> Repo.insert()

    {:ok, snapshot} =
      %PostSnapshot{}
      |> PostSnapshot.changeset(%{
        post_id: post.id,
        version: 1,
        normalized_text: "Hello world",
        submitted_by_session_id: "admin"
      })
      |> Repo.insert()

    {:ok, post} = post |> Post.changeset(%{current_snapshot_id: snapshot.id}) |> Repo.update()
    post
  end
end
