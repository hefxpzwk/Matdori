defmodule MatdoriWeb.MyPageLiveTest do
  use MatdoriWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Matdori.Collab

  test "unauthenticated users are redirected to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/me")
    assert to == ~p"/login"
  end

  test "my page shows created, liked, and highlighted rooms", %{conn: conn} do
    google_uid = "google-my-page-user"

    conn =
      google_auth_conn(conn, %{
        "google_uid" => google_uid,
        "google_name" => "My Page User",
        "display_name" => "My Page User"
      })

    assert {:ok, created_post} =
             Collab.share_post(
               %{
                 "title" => "내가 만든 방",
                 "tweet_url" =>
                   "https://x.com/my_page_created/status/#{System.unique_integer([:positive])}",
                 "google_uid" => google_uid
               },
               "my-page-created-session"
             )

    assert {:ok, liked_post} =
             Collab.share_post(
               %{
                 "title" => "내가 좋아요한 방",
                 "tweet_url" =>
                   "https://x.com/my_page_liked/status/#{System.unique_integer([:positive])}",
                 "google_uid" => "another-user"
               },
               "my-page-liked-owner"
             )

    assert {:ok, highlighted_post} =
             Collab.share_post(
               %{
                 "title" => "내가 하이라이트한 방",
                 "tweet_url" =>
                   "https://x.com/my_page_highlighted/status/#{System.unique_integer([:positive])}",
                 "google_uid" => "another-user-2"
               },
               "my-page-highlight-owner"
             )

    assert {:ok, _} =
             Collab.toggle_reaction(liked_post.id, "my-page-like-session", "like", google_uid)

    snapshot = highlighted_post.current_snapshot

    assert {:ok, _} =
             Collab.create_highlight(snapshot, %{
               "session_id" => "my-page-highlight-session",
               "google_uid" => google_uid,
               "display_name" => "My Page User",
               "color" => "#3b82f6",
               "quote_exact" => "텍스트",
               "quote_prefix" => "",
               "quote_suffix" => "",
               "start_g" => 0,
               "end_g" => 3
             })

    {:ok, view, _html} = live(conn, ~p"/me")

    assert has_element?(view, "#my-page")
    assert has_element?(view, "#my-created-room-#{created_post.id}")
    assert has_element?(view, "#my-liked-room-#{liked_post.id}")
    assert has_element?(view, "#my-highlighted-room-#{highlighted_post.id}")
  end

  test "my page includes overlay-highlighted rooms", %{conn: conn} do
    google_uid = "google-my-page-overlay-user"
    session_id = "my-page-overlay-session"

    conn =
      google_auth_conn(conn, %{
        "google_uid" => google_uid,
        "google_name" => "Overlay User",
        "display_name" => "Overlay User",
        "session_id" => session_id
      })

    assert {:ok, overlay_post} =
             Collab.share_post(
               %{
                 "title" => "오버레이 하이라이트 방",
                 "tweet_url" =>
                   "https://x.com/my_page_overlay/status/#{System.unique_integer([:positive])}",
                 "google_uid" => "overlay-owner"
               },
               "overlay-owner-session"
             )

    assert {:ok, _rows} =
             Collab.replace_overlay_highlights(overlay_post.id, %{
               "session_id" => session_id,
               "display_name" => "Overlay User",
               "color" => "#3b82f6",
               "highlights" => [
                 %{
                   "id" => "overlay-1",
                   "left" => 0.1,
                   "top" => 0.1,
                   "width" => 0.2,
                   "height" => 0.2,
                   "comment" => "overlay"
                 }
               ]
             })

    {:ok, view, _html} = live(conn, ~p"/me")
    assert has_element?(view, "#my-highlighted-room-#{overlay_post.id}")
  end
end
