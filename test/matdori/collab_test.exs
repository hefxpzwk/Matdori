defmodule Matdori.CollabTest do
  use Matdori.DataCase, async: false

  alias Matdori.Collab
  alias Matdori.Collab.{Comment, Highlight, OverlayHighlight, Post, PostSnapshot, Report}

  test "toggle_reaction/3 toggles like and dislike, with single reaction per session" do
    post = insert_post_with_snapshot()

    assert {:ok, _} = Collab.toggle_reaction(post.id, "session-1", "like")
    assert Collab.reaction_count(post.id, "like") == 1
    assert Collab.reaction_count(post.id, "dislike") == 0
    assert Collab.reacted_by?(post.id, "session-1", "like")

    assert {:ok, _} = Collab.toggle_reaction(post.id, "session-1", "dislike")
    assert Collab.reaction_count(post.id, "like") == 0
    assert Collab.reaction_count(post.id, "dislike") == 1
    refute Collab.reacted_by?(post.id, "session-1", "like")
    assert Collab.reacted_by?(post.id, "session-1", "dislike")

    assert {:ok, _} = Collab.toggle_reaction(post.id, "session-1", "dislike")
    assert Collab.reaction_count(post.id, "dislike") == 0
  end

  test "toggle_heart/2 remains compatible as like wrapper" do
    post = insert_post_with_snapshot()

    assert {:ok, _} = Collab.toggle_heart(post.id, "session-1")
    assert Collab.heart_count(post.id) == 1
    assert Collab.hearted_by?(post.id, "session-1")

    assert {:ok, _} = Collab.toggle_heart(post.id, "session-1")
    assert Collab.heart_count(post.id) == 0
    refute Collab.hearted_by?(post.id, "session-1")
  end

  test "toggle_reaction/3 rejects invalid reaction kind" do
    post = insert_post_with_snapshot()

    assert {:error, :invalid_reaction_kind} =
             Collab.toggle_reaction(post.id, "session-1", "smile")

    assert Collab.reaction_count(post.id, "like") == 0
    assert Collab.reaction_count(post.id, "dislike") == 0
  end

  test "list_posts/1 includes like and dislike counts" do
    post = insert_post_with_snapshot()

    assert {:ok, _} = Collab.toggle_reaction(post.id, "session-like", "like")
    assert {:ok, _} = Collab.toggle_reaction(post.id, "session-dislike", "dislike")

    listed_post =
      Collab.list_posts(50)
      |> Enum.find(&(&1.id == post.id))

    assert listed_post
    assert listed_post.like_count == 1
    assert listed_post.dislike_count == 1
  end

  test "register_view/2 counts unique sessions only" do
    post = insert_post_with_snapshot()

    assert :ok = Collab.register_view(post.id, "viewer-1")
    assert :ok = Collab.register_view(post.id, "viewer-1")
    assert :ok = Collab.register_view(post.id, "viewer-2")

    assert Collab.view_count(post.id) == 2

    listed_post =
      Collab.list_posts(50, sort: "views")
      |> Enum.find(&(&1.id == post.id))

    assert listed_post
    assert listed_post.view_count == 2
  end

  test "register_view_with_status/2 returns inserted then existing" do
    post = insert_post_with_snapshot()

    assert :inserted = Collab.register_view_with_status(post.id, "viewer-status")
    assert :existing = Collab.register_view_with_status(post.id, "viewer-status")
    assert :ignored = Collab.register_view_with_status("bad", "viewer-status")
  end

  test "list_posts/2 supports likes and views sorting" do
    first = insert_post_with_snapshot()
    second = insert_post_with_snapshot()

    assert {:ok, _} = Collab.toggle_reaction(first.id, "like-1", "like")
    assert {:ok, _} = Collab.toggle_reaction(first.id, "like-2", "like")
    assert {:ok, _} = Collab.toggle_reaction(second.id, "like-3", "like")

    likes_sorted_ids = Collab.list_posts(50, sort: "likes") |> Enum.map(& &1.id)

    assert Enum.find_index(likes_sorted_ids, &(&1 == first.id)) <
             Enum.find_index(likes_sorted_ids, &(&1 == second.id))

    assert :ok = Collab.register_view(second.id, "view-1")
    assert :ok = Collab.register_view(second.id, "view-2")
    assert :ok = Collab.register_view(first.id, "view-3")

    views_sorted_ids = Collab.list_posts(50, sort: "views") |> Enum.map(& &1.id)

    assert Enum.find_index(views_sorted_ids, &(&1 == second.id)) <
             Enum.find_index(views_sorted_ids, &(&1 == first.id))
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

  test "replace_overlay_highlights/2 persists highlights and replaces same session set" do
    post = insert_post_with_snapshot()

    assert {:ok, first_saved} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "session-overlay-a",
               display_name: "Alice",
               color: "#123456",
               highlights: [
                 %{
                   "id" => "a-1",
                   "left" => 0.1,
                   "top" => 0.2,
                   "width" => 0.25,
                   "height" => 0.3,
                   "comment" => "첫 코멘트"
                 },
                 %{
                   "id" => "a-2",
                   "left" => 0.4,
                   "top" => 0.25,
                   "width" => 0.1,
                   "height" => 0.15,
                   "comment" => "둘째 코멘트"
                 }
               ]
             })

    assert length(first_saved) == 2

    assert Enum.count(
             Collab.list_overlay_highlights(post.id),
             &(&1.session_id == "session-overlay-a")
           ) == 2

    assert {:ok, second_saved} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "session-overlay-a",
               display_name: "Alice",
               color: "#123456",
               highlights: [
                 %{
                   "id" => "a-3",
                   "left" => 0.15,
                   "top" => 0.35,
                   "width" => 0.22,
                   "height" => 0.18,
                   "comment" => "교체됨"
                 }
               ]
             })

    assert length(second_saved) == 1

    assert [%{highlight_key: "a-3", comment: "교체됨"}] =
             Collab.list_overlay_highlights(post.id)
             |> Enum.filter(&(&1.session_id == "session-overlay-a"))
  end

  test "replace_overlay_highlights/2 only replaces requesting session highlights" do
    post = insert_post_with_snapshot()

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "session-overlay-a",
               display_name: "Alice",
               color: "#111111",
               highlights: [
                 %{"id" => "a-1", "left" => 0.1, "top" => 0.1, "width" => 0.2, "height" => 0.2}
               ]
             })

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "session-overlay-b",
               display_name: "Bob",
               color: "#222222",
               highlights: [
                 %{"id" => "b-1", "left" => 0.5, "top" => 0.2, "width" => 0.2, "height" => 0.2}
               ]
             })

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "session-overlay-a",
               display_name: "Alice",
               color: "#111111",
               highlights: []
             })

    remaining = Collab.list_overlay_highlights(post.id)

    assert Enum.any?(
             remaining,
             &(&1.session_id == "session-overlay-b" and &1.highlight_key == "b-1")
           )

    refute Enum.any?(remaining, &(&1.session_id == "session-overlay-a"))
  end

  test "update_overlay_highlight_comment/3 updates existing highlight comment" do
    post = insert_post_with_snapshot()

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "session-overlay-a",
               display_name: "Alice",
               color: "#111111",
               highlights: [
                 %{
                   "id" => "a-1",
                   "left" => 0.1,
                   "top" => 0.1,
                   "width" => 0.2,
                   "height" => 0.2,
                   "comment" => "초기 코멘트"
                 }
               ]
             })

    assert {:ok, updated} =
             Collab.update_overlay_highlight_comment(post.id, "a-1", %{comment: "업데이트됨"})

    assert updated.highlight_key == "a-1"
    assert updated.comment == "업데이트됨"

    assert [%{highlight_key: "a-1", comment: "업데이트됨"}] =
             Collab.list_overlay_highlights(post.id)
  end

  test "overlay highlight comments support multiple users and delete own comment" do
    post = insert_post_with_snapshot()

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "overlay-owner",
               display_name: "Owner",
               color: "#111111",
               highlights: [
                 %{"id" => "a-1", "left" => 0.1, "top" => 0.1, "width" => 0.2, "height" => 0.2}
               ]
             })

    assert {:ok, first_comment} =
             Collab.create_overlay_highlight_comment(post.id, "a-1", %{
               "session_id" => "overlay-owner",
               "google_uid" => "owner-uid",
               "display_name" => "Owner",
               "color" => "#111111",
               "body" => "첫 댓글"
             })

    assert {:ok, second_comment} =
             Collab.create_overlay_highlight_comment(post.id, "a-1", %{
               "session_id" => "overlay-third",
               "google_uid" => "third-uid",
               "display_name" => "Third",
               "color" => "#222222",
               "body" => "세번째 사용자 댓글"
             })

    comments = Collab.list_overlay_highlight_comments(post.id)

    assert Enum.count(comments, &(&1.highlight_id == "a-1")) == 2
    assert Enum.any?(comments, &(&1.id == first_comment.id and &1.body == "첫 댓글"))
    assert Enum.any?(comments, &(&1.id == second_comment.id and &1.body == "세번째 사용자 댓글"))

    assert {:error, :forbidden} =
             Collab.soft_delete_overlay_highlight_comment(
               post.id,
               first_comment.id,
               "overlay-third",
               "third-uid"
             )

    assert {:ok, _} =
             Collab.soft_delete_overlay_highlight_comment(
               post.id,
               first_comment.id,
               "overlay-owner",
               "owner-uid"
             )

    remaining = Collab.list_overlay_highlight_comments(post.id)
    assert Enum.count(remaining, &(&1.highlight_id == "a-1")) == 1
    assert Enum.any?(remaining, &(&1.id == second_comment.id))
  end

  test "overlay highlight comment delete allows same google_uid from another session" do
    post = insert_post_with_snapshot()

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "overlay-owner-a",
               google_uid: "owner-uid",
               display_name: "Owner",
               color: "#111111",
               highlights: [
                 %{"id" => "a-1", "left" => 0.1, "top" => 0.1, "width" => 0.2, "height" => 0.2}
               ]
             })

    assert {:ok, comment} =
             Collab.create_overlay_highlight_comment(post.id, "a-1", %{
               "session_id" => "overlay-owner-a",
               "google_uid" => "owner-uid",
               "display_name" => "Owner",
               "color" => "#111111",
               "body" => "삭제 예정 댓글"
             })

    assert {:ok, _} =
             Collab.soft_delete_overlay_highlight_comment(
               post.id,
               comment.id,
               "overlay-owner-b",
               "owner-uid"
             )

    assert Collab.list_overlay_highlight_comments(post.id) == []
  end

  test "upsert_profile_by_google_uid/2 syncs display_name to authored artifacts" do
    post = insert_post_with_snapshot()
    snapshot = Repo.preload(post, :current_snapshot).current_snapshot
    google_uid = "google-sync-user"

    assert {:ok, highlight} =
             Collab.create_highlight(snapshot, %{
               "session_id" => "sync-session",
               "google_uid" => google_uid,
               "display_name" => "이전 이름",
               "color" => "#111111",
               "quote_exact" => "Hello",
               "quote_prefix" => "",
               "quote_suffix" => "",
               "start_g" => 0,
               "end_g" => 5
             })

    assert {:ok, _comment} =
             Collab.create_comment(highlight.id, %{
               "session_id" => "sync-session",
               "google_uid" => google_uid,
               "display_name" => "이전 이름",
               "color" => "#111111",
               "body" => "이전 댓글"
             })

    assert {:ok, _report} =
             Collab.create_report(post.id, %{
               "session_id" => "sync-session",
               "google_uid" => google_uid,
               "display_name" => "이전 이름",
               "reason" => "충분히 긴 신고 사유"
             })

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "sync-session",
               google_uid: google_uid,
               display_name: "이전 이름",
               color: "#111111",
               highlights: [
                 %{
                   "id" => "sync-overlay",
                   "left" => 0.1,
                   "top" => 0.1,
                   "width" => 0.2,
                   "height" => 0.2,
                   "comment" => "메모"
                 }
               ]
             })

    assert {:ok, _profile} =
             Collab.upsert_profile_by_google_uid(google_uid, %{
               display_name: "새 이름",
               interests: ["AI"],
               color: "#ef4444"
             })

    assert Repo.get!(Highlight, highlight.id).display_name == "새 이름"
    assert Repo.get!(Highlight, highlight.id).color == "#ef4444"

    assert Repo.one!(
             from c in Comment, where: c.google_uid == ^google_uid, select: c.display_name
           ) ==
             "새 이름"

    assert Repo.one!(from r in Report, where: r.google_uid == ^google_uid, select: r.display_name) ==
             "새 이름"

    assert Repo.one!(
             from o in OverlayHighlight,
               where: o.google_uid == ^google_uid,
               select: o.display_name
           ) == "새 이름"

    assert Repo.one!(
             from o in OverlayHighlight,
               where: o.google_uid == ^google_uid,
               select: o.color
           ) == "#ef4444"

    assert Repo.one!(from c in Comment, where: c.google_uid == ^google_uid, select: c.color) ==
             "#ef4444"
  end

  test "update_display_name_by_google_uid/2 syncs historical authored records" do
    post = insert_post_with_snapshot()
    google_uid = "google-sync-update-name"

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "session-1",
               google_uid: google_uid,
               display_name: "이전 이름",
               color: "#111111",
               highlights: [
                 %{
                   "id" => "old-overlay-1",
                   "left" => 0.1,
                   "top" => 0.1,
                   "width" => 0.2,
                   "height" => 0.2
                 }
               ]
             })

    {:ok, _comment} =
      Collab.create_room_comment(post.id, %{
        "session_id" => "session-1",
        "google_uid" => google_uid,
        "display_name" => "이전 이름",
        "color" => "#111111",
        "body" => "room comment"
      })

    assert {:ok, _profile} =
             Collab.update_display_name_by_google_uid(google_uid, "새로운 이름")

    assert Repo.one!(
             from o in OverlayHighlight,
               where: o.google_uid == ^google_uid,
               where: o.post_id == ^post.id,
               select: o.display_name
           ) == "새로운 이름"

    assert Repo.one!(
             from c in Comment,
               where: c.google_uid == ^google_uid,
               where: c.post_id == ^post.id,
               select: c.display_name
           ) == "새로운 이름"
  end

  test "delete_post_by_owner/2 hides only owner-created post" do
    owner_uid = "google-room-owner"

    assert {:ok, owned_post} =
             Collab.share_post(
               %{
                 "title" => "내 방",
                 "tweet_url" =>
                   "https://x.com/owner/status/#{System.unique_integer([:positive])}",
                 "google_uid" => owner_uid
               },
               "owner-session"
             )

    assert {:error, :forbidden} = Collab.delete_post_by_owner(owned_post.id, "google-other-user")

    assert {:ok, hidden_post} = Collab.delete_post_by_owner(owned_post.id, owner_uid)
    assert hidden_post.hidden == true
    assert hidden_post.hidden_reason == "deleted_by_owner"
  end

  test "delete_highlights_for_user_in_post/3 removes only own text/overlay highlights" do
    post = insert_post_with_snapshot()
    snapshot = Repo.preload(post, :current_snapshot).current_snapshot

    owner_uid = "google-highlight-owner"
    owner_session = "owner-session"
    other_uid = "google-highlight-other"

    assert {:ok, _} =
             Collab.create_highlight(snapshot, %{
               "session_id" => owner_session,
               "google_uid" => owner_uid,
               "display_name" => "Owner",
               "color" => "#111111",
               "quote_exact" => "Hello",
               "quote_prefix" => "",
               "quote_suffix" => "",
               "start_g" => 0,
               "end_g" => 5
             })

    assert {:ok, _} =
             Collab.create_highlight(snapshot, %{
               "session_id" => "other-session",
               "google_uid" => other_uid,
               "display_name" => "Other",
               "color" => "#222222",
               "quote_exact" => "world",
               "quote_prefix" => "",
               "quote_suffix" => "",
               "start_g" => 6,
               "end_g" => 11
             })

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: owner_session,
               google_uid: owner_uid,
               display_name: "Owner",
               color: "#111111",
               highlights: [
                 %{
                   "id" => "owner-overlay",
                   "left" => 0.1,
                   "top" => 0.1,
                   "width" => 0.2,
                   "height" => 0.2
                 }
               ]
             })

    assert {:ok, _} =
             Collab.replace_overlay_highlights(post.id, %{
               session_id: "other-session",
               google_uid: other_uid,
               display_name: "Other",
               color: "#222222",
               highlights: [
                 %{
                   "id" => "other-overlay",
                   "left" => 0.4,
                   "top" => 0.4,
                   "width" => 0.2,
                   "height" => 0.2
                 }
               ]
             })

    assert {:ok, %{deleted_total: 2, deleted_text: 1, deleted_overlay: 1}} =
             Collab.delete_highlights_for_user_in_post(post.id, owner_uid, owner_session)

    remaining_text = Repo.all(from h in Highlight, where: h.post_snapshot_id == ^snapshot.id)
    remaining_overlay = Repo.all(from h in OverlayHighlight, where: h.post_id == ^post.id)

    assert Enum.count(remaining_text) == 1
    assert Enum.all?(remaining_text, &(&1.google_uid == other_uid))
    assert Enum.count(remaining_overlay) == 1
    assert Enum.all?(remaining_overlay, &(&1.google_uid == other_uid))
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

  test "latest and list_posts include posts from any account" do
    first_id = Integer.to_string(System.unique_integer([:positive]))
    second_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, %{inserted_or_updated: 2}} =
             Collab.sync_configured_account_posts(
               source_posts: [
                 %{
                   tweet_id: first_id,
                   tweet_url: "https://x.com/someone/status/#{first_id}",
                   snapshot_text: "first post",
                   posted_at: ~U[2026-03-06 09:00:00Z]
                 },
                 %{
                   tweet_id: second_id,
                   tweet_url: "https://x.com/another/status/#{second_id}",
                   snapshot_text: "second post",
                   posted_at: ~U[2026-03-06 11:00:00Z]
                 }
               ],
               session_id: "sync-any-account"
             )

    latest = Collab.get_latest_post_with_versions()
    assert latest.tweet_id == second_id

    posts = Collab.list_posts(10)
    assert Enum.any?(posts, &(&1.tweet_id == first_id))
    assert Enum.any?(posts, &(&1.tweet_id == second_id))
  end

  test "share_post/2 creates room from arbitrary x post URL" do
    id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, post} =
             Collab.share_post(
               %{
                 "title" => "공유 테스트",
                 "tweet_url" => "https://twitter.com/random_user/status/#{id}?s=20",
                 "snapshot_text" => "shared text"
               },
               "share-session"
             )

    assert post.tweet_id == id
    assert post.tweet_url == "https://x.com/random_user/status/#{id}"
    assert post.title == "공유 테스트"

    loaded = Collab.get_post_with_versions(post.id)
    assert loaded.current_snapshot.normalized_text == "shared text"
  end

  test "share_post/2 creates room from generic link" do
    assert {:ok, post} =
             Collab.share_post(
               %{
                 "title" => "일반 링크 공유",
                 "tweet_url" => "https://example.com/article?id=1#section"
               },
               "share-session"
             )

    assert post.tweet_url == "https://example.com/article?id=1"
    assert post.tweet_id =~ "url-"
    assert post.title == "일반 링크 공유"
  end

  test "share_post/2 creates separate rooms for different non-embed links" do
    assert {:ok, first} =
             Collab.share_post(
               %{"title" => "첫 링크", "tweet_url" => "https://example.com/a"},
               "share-session"
             )

    assert {:ok, second} =
             Collab.share_post(
               %{"title" => "둘째 링크", "tweet_url" => "https://example.com/b"},
               "share-session"
             )

    assert first.id != second.id
    assert first.tweet_id != second.tweet_id
  end

  test "share_post/2 rejects invalid url" do
    assert {:error, :invalid_tweet_url} =
             Collab.share_post(
               %{"title" => "링크 에러", "tweet_url" => "not-a-url"},
               "share-session"
             )
  end

  test "share_post/2 rejects empty title" do
    assert {:error, :invalid_title} =
             Collab.share_post(
               %{"title" => "  ", "tweet_url" => "https://x.com/user/status/100"},
               "share-session"
             )
  end

  test "share_post/2 does not overwrite title or chronology on re-share" do
    id = Integer.to_string(System.unique_integer([:positive]))
    url = "https://x.com/reuse_user/status/#{id}"

    assert {:ok, first} =
             Collab.share_post(
               %{"title" => "첫 제목", "tweet_url" => url},
               "share-session-1"
             )

    assert {:ok, second} =
             Collab.share_post(
               %{"title" => "다른 제목", "tweet_url" => url},
               "share-session-2"
             )

    assert first.id == second.id

    loaded = Collab.get_post_with_versions(first.id)
    assert loaded.title == "첫 제목"
    assert loaded.tweet_posted_at == first.tweet_posted_at
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
