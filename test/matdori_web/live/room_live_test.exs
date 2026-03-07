defmodule MatdoriWeb.RoomLiveTest do
  use MatdoriWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Matdori.Collab
  alias MatdoriWeb.Presence

  test "x room shows native embed status", %{conn: conn} do
    id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, post} =
             Collab.share_post(
               %{"title" => "X 방", "tweet_url" => "https://x.com/native_user/status/#{id}"},
               "room-live-x"
             )

    {:ok, view, _html} = live(conn, ~p"/rooms/#{post.id}")

    assert has_element?(view, "#room-collab-stage[phx-hook='SnapshotCanvas']")
    assert has_element?(view, "#room-remote-cursors[phx-hook='RemoteCursors']")
    assert has_element?(view, "#room-presence-count", "현재 접속 1명")
    assert has_element?(view, "#room-embed-status")
    assert has_element?(view, "#room-view-count", "조회수 1")
    assert has_element?(view, "#embed-highlight-mode-toggle")
    assert has_element?(view, "#embed-highlight-clear")
    assert has_element?(view, "#embed-highlight-count", "0개 선택됨")
    assert has_element?(view, "#embed-highlight-comment-panel.hidden")
    assert has_element?(view, "#embed-highlight-comment-input")
    assert has_element?(view, "#embed-highlight-comment-save")
    assert has_element?(view, "#room-embed-highlight-overlay[phx-hook='EmbedHighlightOverlay']")
    assert has_element?(view, "#room-embed-highlight-overlay[data-session-id][data-user-color]")
    assert render(view) =~ "임베드 가능"
    assert render(view) =~ "조회수"
    assert has_element?(view, "#tweet-embed")
    refute has_element?(view, "#link-card-list")
    refute has_element?(view, "#youtube-embed")
  end

  test "youtube room auto-embeds video iframe", %{conn: conn} do
    assert {:ok, post} =
             Collab.share_post(
               %{
                 "title" => "유튜브 방",
                 "tweet_url" =>
                   "https://www.youtube.com/watch?v=iI5AmA9Vnhk&list=LL&index=1&t=285s"
               },
               "room-live-youtube"
             )

    {:ok, view, _html} = live(conn, ~p"/rooms/#{post.id}")

    assert has_element?(view, "#room-embed-status")
    assert render(view) =~ "임베드 가능"
    assert has_element?(view, "#youtube-embed")
    assert has_element?(view, "#youtube-embed[src*='youtube.com/embed/iI5AmA9Vnhk']")
    assert has_element?(view, "#room-embed-highlight-overlay")
    refute has_element?(view, "#tweet-embed")
    refute has_element?(view, "#link-card-list")
  end

  test "generic link room shows preview status", %{conn: conn} do
    assert {:ok, post} =
             Collab.share_post(
               %{"title" => "블로그 방", "tweet_url" => "https://example.com/posts/hello-world"},
               "room-live-generic"
             )

    {:ok, view, _html} = live(conn, ~p"/rooms/#{post.id}")

    assert has_element?(view, "#room-embed-status")
    assert render(view) =~ "미리보기"
    assert has_element?(view, "#link-preview-card")
    assert has_element?(view, "#room-embed-highlight-overlay")

    assert has_element?(
             view,
             "#preview-card-source[href='https://example.com/posts/hello-world']"
           )

    refute has_element?(view, "#link-card-list")
    refute has_element?(view, "#tweet-embed")
  end

  test "preview card renders og image when metadata exists", %{conn: conn} do
    id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, %{inserted_or_updated: 1}} =
             Collab.sync_configured_account_posts(
               source_posts: [
                 %{
                   title: "OG 카드",
                   tweet_id: id,
                   tweet_url: "https://blog.example.com/og-card",
                   preview_description: "미리보기 설명",
                   preview_image_url: "https://images.example.com/og-card.png",
                   snapshot_text: "본문",
                   posted_at: ~U[2026-03-06 15:00:00Z]
                 }
               ],
               session_id: "room-live-og"
             )

    post = Collab.get_latest_post_with_versions()
    {:ok, view, _html} = live(conn, ~p"/rooms/#{post.id}")

    assert has_element?(view, "#preview-card-image")
    assert render(view) =~ "미리보기 설명"
  end

  test "non-embed room does not show other non-embed rooms", %{conn: conn} do
    assert {:ok, first} =
             Collab.share_post(
               %{"title" => "첫번째 링크", "tweet_url" => "https://example.com/posts/first"},
               "room-live-generic-a"
             )

    assert {:ok, _second} =
             Collab.share_post(
               %{"title" => "두번째 링크", "tweet_url" => "https://example.com/posts/second"},
               "room-live-generic-b"
             )

    {:ok, view, _html} = live(conn, ~p"/rooms/#{first.id}")

    assert render(view) =~ "첫번째 링크"
    refute render(view) =~ "두번째 링크"
    assert has_element?(view, "#link-preview-card")
  end

  test "room supports like and dislike toggles", %{conn: conn} do
    id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, post} =
             Collab.share_post(
               %{"title" => "반응 테스트", "tweet_url" => "https://x.com/reaction_user/status/#{id}"},
               "room-live-reaction-owner"
             )

    conn_a = init_test_session(conn, %{"session_id" => "session-a"})
    conn_b = init_test_session(conn, %{"session_id" => "session-b"})

    {:ok, view_a, _html} = live(conn_a, ~p"/rooms/#{post.id}")
    {:ok, view_b, _html} = live(conn_b, ~p"/rooms/#{post.id}")

    presence_diff = %Phoenix.Socket.Broadcast{
      topic: "presence:test",
      event: "presence_diff",
      payload: %{}
    }

    send(view_a.pid, presence_diff)
    send(view_b.pid, presence_diff)
    send(view_a.pid, {:room_refresh, post.id})
    send(view_b.pid, {:room_refresh, post.id})

    assert has_element?(view_a, "#room-view-count", "조회수 2")
    assert has_element?(view_b, "#room-view-count", "조회수 2")
    assert has_element?(view_a, "#room-presence-count", "현재 접속 2명")
    assert has_element?(view_b, "#room-presence-count", "현재 접속 2명")
    assert has_element?(view_a, "#room-presence-user-session-a")
    assert has_element?(view_a, "#room-presence-user-session-b")
    assert has_element?(view_a, "#like-count", "0")
    assert has_element?(view_a, "#dislike-count", "0")

    view_a |> element("#like-button") |> render_click()

    assert has_element?(view_a, "#like-count", "1")
    assert has_element?(view_a, "#dislike-count", "0")
    assert has_element?(view_b, "#like-count", "1")

    view_b |> element("#dislike-button") |> render_click()

    assert has_element?(view_a, "#like-count", "1")
    assert has_element?(view_a, "#dislike-count", "1")
    assert has_element?(view_b, "#dislike-count", "1")

    view_a |> element("#like-button") |> render_click()

    assert has_element?(view_a, "#like-count", "0")
    assert has_element?(view_a, "#dislike-count", "1")
    assert has_element?(view_b, "#like-count", "0")
  end

  test "overlay highlights are synced to presence metadata", %{conn: conn} do
    id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, post} =
             Collab.share_post(
               %{"title" => "오버레이 동기화", "tweet_url" => "https://x.com/overlay_user/status/#{id}"},
               "room-live-overlay-sync"
             )

    conn_a = init_test_session(conn, %{"session_id" => "overlay-session-a"})
    conn_b = init_test_session(conn, %{"session_id" => "overlay-session-b"})

    {:ok, view_a, _html} = live(conn_a, ~p"/rooms/#{post.id}")
    {:ok, _view_b, _html} = live(conn_b, ~p"/rooms/#{post.id}")

    render_hook(view_a, "overlay_highlight_draft", %{
      "zone" => %{"left" => 0.12, "top" => 0.22, "width" => 0.2, "height" => 0.15}
    })

    assert %{"overlay-session-a" => %{metas: [draft_meta | _]}} =
             Presence.list("presence:#{post.id}")

    assert draft_meta.overlay_highlight_draft.left == 0.12
    assert draft_meta.overlay_highlight_draft.top == 0.22
    assert draft_meta.overlay_highlight_draft.width == 0.2
    assert draft_meta.overlay_highlight_draft.height == 0.15

    render_hook(view_a, "overlay_highlights_sync", %{
      "highlights" => [
        %{
          "id" => "mine-1",
          "left" => 0.1,
          "top" => 0.2,
          "width" => 0.25,
          "height" => 0.3,
          "comment" => "여기에 코멘트"
        }
      ]
    })

    assert %{"overlay-session-a" => %{metas: [meta | _]}} = Presence.list("presence:#{post.id}")

    assert [zone] = meta.overlay_highlights
    assert zone.left == 0.1
    assert zone.top == 0.2
    assert zone.width == 0.25
    assert zone.height == 0.3
    assert zone.id == "mine-1"
    assert zone.comment == "여기에 코멘트"
    assert is_nil(meta.overlay_highlight_draft)

    render_hook(view_a, "overlay_highlight_draft", %{"zone" => nil})

    assert %{"overlay-session-a" => %{metas: [draft_cleared | _]}} =
             Presence.list("presence:#{post.id}")

    assert is_nil(draft_cleared.overlay_highlight_draft)

    render_hook(view_a, "overlay_highlights_sync", %{"highlights" => []})

    assert %{"overlay-session-a" => %{metas: [cleared_meta | _]}} =
             Presence.list("presence:#{post.id}")

    assert cleared_meta.overlay_highlights == []
  end
end
