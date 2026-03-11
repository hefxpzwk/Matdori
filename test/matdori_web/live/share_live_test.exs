defmodule MatdoriWeb.ShareLiveTest do
  use MatdoriWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Matdori.Collab
  alias MatdoriWeb.Presence

  test "main page shows latest rooms feed below composer", %{conn: conn} do
    conn = google_auth_conn(conn)
    older_id = Integer.to_string(System.unique_integer([:positive]))
    newer_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, older} =
             Collab.share_post(
               %{
                 "title" => "feed-older",
                 "tweet_url" => "https://x.com/feed_user/status/#{older_id}"
               },
               "share-feed-older"
             )

    assert {:ok, newer} =
             Collab.share_post(
               %{
                 "title" => "feed-newer",
                 "tweet_url" => "https://x.com/feed_user/status/#{newer_id}"
               },
               "share-feed-newer"
             )

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#share-feed")
    assert has_element?(view, "#share-feed-sort-form")

    latest_html = render(view)

    assert html_position(latest_html, ~s(id="share-feed-item-#{newer.id}")) <
             html_position(latest_html, ~s(id="share-feed-item-#{older.id}"))
  end

  test "main page supports views and realtime sorting", %{conn: conn} do
    conn = google_auth_conn(conn)
    first_id = Integer.to_string(System.unique_integer([:positive]))
    second_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, first} =
             Collab.share_post(
               %{
                 "title" => "real-first",
                 "tweet_url" => "https://x.com/share_sort_user/status/#{first_id}"
               },
               "share-sort-first"
             )

    assert {:ok, second} =
             Collab.share_post(
               %{
                 "title" => "real-second",
                 "tweet_url" => "https://x.com/share_sort_user/status/#{second_id}"
               },
               "share-sort-second"
             )

    assert :ok = Collab.register_view(second.id, "share-sort-view-1")
    assert :ok = Collab.register_view(second.id, "share-sort-view-2")
    assert :ok = Collab.register_view(first.id, "share-sort-view-3")

    {:ok, view, _html} = live(conn, ~p"/")

    _html =
      view
      |> form("#share-feed-sort-form", %{sort: "views"})
      |> render_change()

    views_html = render(view)

    assert html_position(views_html, ~s(id="share-feed-item-#{second.id}")) <
             html_position(views_html, ~s(id="share-feed-item-#{first.id}"))

    assert {:ok, _meta} =
             Presence.track(self(), "presence:#{first.id}", "share-live-presence-#{first.id}", %{
               display_name: "share-live-user"
             })

    _html =
      view
      |> form("#share-feed-sort-form", %{sort: "live"})
      |> render_change()

    live_html = render(view)

    assert html_position(live_html, ~s(id="share-feed-item-#{first.id}")) <
             html_position(live_html, ~s(id="share-feed-item-#{second.id}"))
  end

  test "topbar trending links to most active room when active rooms exist", %{conn: conn} do
    conn = google_auth_conn(conn)

    first_id = Integer.to_string(System.unique_integer([:positive]))
    second_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, first} =
             Collab.share_post(
               %{
                 "title" => "trend-active-first",
                 "tweet_url" => "https://x.com/trend_active/status/#{first_id}"
               },
               "trend-active-first"
             )

    assert {:ok, second} =
             Collab.share_post(
               %{
                 "title" => "trend-active-second",
                 "tweet_url" => "https://x.com/trend_active/status/#{second_id}"
               },
               "trend-active-second"
             )

    assert {:ok, _meta} =
             Presence.track(self(), "presence:#{first.id}", "trend-first-1", %{
               display_name: "user-1"
             })

    assert {:ok, _meta} =
             Presence.track(self(), "presence:#{second.id}", "trend-second-1", %{
               display_name: "user-2"
             })

    assert {:ok, _meta} =
             Presence.track(self(), "presence:#{second.id}", "trend-second-2", %{
               display_name: "user-3"
             })

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "a.x-top-nav-item[href='/rooms/#{second.id}']", "Trending")
  end

  test "topbar trending links to most viewed room when no active rooms exist", %{conn: conn} do
    conn = google_auth_conn(conn)

    low_id = Integer.to_string(System.unique_integer([:positive]))
    high_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, low_views} =
             Collab.share_post(
               %{
                 "title" => "trend-views-low",
                 "tweet_url" => "https://x.com/trend_views/status/#{low_id}"
               },
               "trend-views-low"
             )

    assert {:ok, high_views} =
             Collab.share_post(
               %{
                 "title" => "trend-views-high",
                 "tweet_url" => "https://x.com/trend_views/status/#{high_id}"
               },
               "trend-views-high"
             )

    assert :ok = Collab.register_view(high_views.id, "trend-views-1")
    assert :ok = Collab.register_view(high_views.id, "trend-views-2")
    assert :ok = Collab.register_view(low_views.id, "trend-views-3")

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "a.x-top-nav-item[href='/rooms/#{high_views.id}']", "Trending")
  end

  test "create query param opens centered create modal", %{conn: conn} do
    conn = google_auth_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/?create=1")

    assert has_element?(view, "#share-create-modal-backdrop")
    assert has_element?(view, "#share-create-form")
    assert has_element?(view, "#share-create-link-url")
    assert has_element?(view, "#share-title")
  end

  test "users can navigate to existing room by searching link", %{conn: conn} do
    id = Integer.to_string(System.unique_integer([:positive]))
    url = "https://x.com/community_user/status/#{id}"
    {:ok, post} = Collab.share_post(%{"title" => "기존 방", "tweet_url" => url}, "seed-session")

    conn = google_auth_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#share-room-form",
               share: %{
                 tweet_url: url
               }
             )
             |> render_submit()

    assert to == ~p"/rooms/#{post.id}"
  end

  test "searching without link shows validation feedback", %{conn: conn} do
    conn = google_auth_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    _html =
      view
      |> form("#share-room-form",
        share: %{
          tweet_url: ""
        }
      )
      |> render_submit()

    assert render(view) =~ "Please enter a link."
  end

  test "searching unknown link shows info and keeps search button", %{conn: conn} do
    conn = google_auth_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")
    id = Integer.to_string(System.unique_integer([:positive]))
    url = "https://x.com/community_user/status/#{id}"

    _html =
      view
      |> form("#share-room-form",
        share: %{
          tweet_url: url
        }
      )
      |> render_submit()

    assert render(view) =~ "No room found for this link."
    assert has_element?(view, "#share-room-search")
    refute has_element?(view, "#share-room-start-create")
  end

  test "users can create new room from create modal", %{conn: conn} do
    conn = google_auth_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/?create=1")
    id = Integer.to_string(System.unique_integer([:positive]))
    url = "https://x.com/community_user/status/#{id}"

    assert has_element?(view, "#share-create-form")
    assert has_element?(view, "#share-room-submit")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#share-create-form",
               share: %{
                 title: "같이 읽고 싶은 글",
                 tweet_url: url
               }
             )
             |> render_submit()

    assert to =~ ~r|^/rooms/\d+$|

    latest = Collab.get_latest_post_with_versions()
    assert latest.title == "같이 읽고 싶은 글"
    assert latest.tweet_id == id
  end

  test "users can create room from generic web link", %{conn: conn} do
    conn = google_auth_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/?create=1")
    url = "https://example.com/articles/notion-like-embed"

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#share-create-form",
               share: %{
                 title: "블로그 공유",
                 tweet_url: url
               }
             )
             |> render_submit()

    assert to =~ ~r|^/rooms/\d+$|

    latest = Collab.get_latest_post_with_versions()
    assert latest.title == "블로그 공유"
    assert latest.tweet_id =~ "url-"
  end

  test "title is required when creating room", %{conn: conn} do
    conn = google_auth_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/?create=1")
    id = Integer.to_string(System.unique_integer([:positive]))
    url = "https://x.com/community_user/status/#{id}"

    _html =
      view
      |> form("#share-create-form",
        share: %{
          title: "",
          tweet_url: url
        }
      )
      |> render_submit()

    assert render(view) =~ "Please enter a title."
  end

  test "invalid url shows validation feedback", %{conn: conn} do
    conn = google_auth_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/")

    _html =
      view
      |> form("#share-room-form",
        share: %{
          tweet_url: "not-a-url"
        }
      )
      |> render_submit()

    assert render(view) =~ "Please enter a valid link."
  end

  test "creating with existing url shows info and navigates to that room", %{conn: conn} do
    conn = google_auth_conn(conn)
    existing_id = Integer.to_string(System.unique_integer([:positive]))
    existing_url = "https://x.com/community_user/status/#{existing_id}"

    {:ok, post} =
      Collab.share_post(%{"title" => "existing-room", "tweet_url" => existing_url}, "seed-dup")

    {:ok, view, _html} = live(conn, ~p"/?create=1")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#share-create-form",
               share: %{
                 title: "new title",
                 tweet_url: existing_url
               }
             )
             |> render_submit()

    assert to == ~p"/rooms/#{post.id}"
  end

  test "unauthenticated users can only read and see login CTA", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#share-login-required")
    assert has_element?(view, "#share-login-link")
    assert has_element?(view, "#share-room-form")
  end

  defp html_position(html, needle) do
    case :binary.match(html, needle) do
      {index, _length} -> index
      :nomatch -> flunk("Expected to find #{needle} in HTML")
    end
  end
end
