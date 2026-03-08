defmodule MatdoriWeb.MyPageLiveTest do
  use MatdoriWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Matdori.Collab

  test "unauthenticated users are redirected to login", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/me")
    assert to == ~p"/login"
  end

  test "my page shows profile header and tabbed room sections", %{conn: conn} do
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
               "quote_exact" => "This",
               "quote_prefix" => "",
               "quote_suffix" => "",
               "start_g" => 0,
               "end_g" => 4
             })

    {:ok, view, _html} = live(conn, ~p"/me")

    assert has_element?(view, "#my-page")
    assert has_element?(view, "#profile-topbar-back")
    assert has_element?(view, "#profile-topbar-title", "Profile")
    assert has_element?(view, "#my-profile-header")
    assert has_element?(view, "#my-profile-name", "My Page User")
    assert has_element?(view, "#my-profile-interest")
    refute render(view) =~ "협업 리딩"
    assert has_element?(view, "#my-tab-created")
    assert has_element?(view, "#my-tab-highlighted")
    assert has_element?(view, "#my-tab-liked")
    assert has_element?(view, "#my-profile-edit-toggle")
    assert has_element?(view, "#my-profile-color")
    refute has_element?(view, "#my-profile-edit-modal")

    assert has_element?(view, "#my-created-room-#{created_post.id}")
    assert has_element?(view, "#my-created-delete-#{created_post.id}")
    refute has_element?(view, "#my-liked-room-#{liked_post.id}")
    refute has_element?(view, "#my-highlighted-room-#{highlighted_post.id}")

    _html = view |> element("#my-tab-liked") |> render_click()
    assert has_element?(view, "#my-liked-room-#{liked_post.id}")
    refute has_element?(view, "#my-created-room-#{created_post.id}")

    _html = view |> element("#my-tab-highlighted") |> render_click()
    assert has_element?(view, "#my-highlighted-room-#{highlighted_post.id}")
    assert has_element?(view, "#my-highlighted-delete-#{highlighted_post.id}")
    refute has_element?(view, "#my-liked-room-#{liked_post.id}")

    _html = view |> element("#my-highlighted-delete-#{highlighted_post.id}") |> render_click()
    refute has_element?(view, "#my-highlighted-room-#{highlighted_post.id}")
    assert has_element?(view, "#my-highlighted-empty")

    _html = view |> element("#my-tab-created") |> render_click()
    assert has_element?(view, "#my-created-room-#{created_post.id}")
    _html = view |> element("#my-created-delete-#{created_post.id}") |> render_click()
    refute has_element?(view, "#my-created-room-#{created_post.id}")
    assert has_element?(view, "#my-created-empty")

    _html = view |> element("#my-profile-edit-toggle") |> render_click()
    assert has_element?(view, "#my-profile-edit-modal")
    assert has_element?(view, "#my-profile-edit-form")
    assert has_element?(view, "#my-profile-name-input")
    assert has_element?(view, "#my-profile-interests-input")
    assert has_element?(view, "#my-profile-color-input")
    assert has_element?(view, "#my-profile-color-presets")

    _html = view |> element("#my-profile-color-preset-ef4444") |> render_click()

    _html =
      view
      |> form("#my-profile-edit-form", %{
        "profile" => %{
          "display_name" => "수정된 유저",
          "interests_input" => "AI · 디자인 시스템, 제품 전략, AI · 디자인 시스템",
          "color" => "#ef4444"
        }
      })
      |> render_submit()

    assert has_element?(view, "#my-profile-name", "수정된 유저")
    assert has_element?(view, "#my-profile-interest", "AI · 디자인 시스템")
    assert has_element?(view, "#my-profile-interest", "제품 전략")
    refute has_element?(view, "#my-profile-edit-modal")

    assert %{color: "#ef4444"} = Collab.get_profile_by_google_uid(google_uid)

    _html = view |> element("#profile-topbar-title") |> render_click()

    refute has_element?(view, "#my-highlighted-room-#{highlighted_post.id}")
    assert has_element?(view, "#my-profile-name", "수정된 유저")
    assert has_element?(view, "#my-profile-interest", "AI · 디자인 시스템")
  end

  test "profile edit validates blank display name", %{conn: conn} do
    conn = google_auth_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/me")

    _html = view |> element("#my-profile-edit-toggle") |> render_click()

    _html =
      view
      |> form("#my-profile-edit-form", %{
        "profile" => %{"display_name" => "", "interests_input" => "AI"}
      })
      |> render_submit()

    assert render(view) =~ "Please enter a username."
    assert has_element?(view, "#my-profile-edit-modal")
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
    _html = view |> element("#my-tab-highlighted") |> render_click()
    assert has_element?(view, "#my-highlighted-room-#{overlay_post.id}")
  end
end
