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

    assert render(view) =~ "링크를 입력해 주세요"
  end

  test "users can switch to create mode and create new room", %{conn: conn} do
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

    assert has_element?(view, "#share-room-start-create")
    refute has_element?(view, "#share-title")

    _html =
      view
      |> element("#share-room-start-create")
      |> render_click()

    assert has_element?(view, "#share-title")
    assert has_element?(view, "#share-room-submit")
    refute has_element?(view, "#share-room-search")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#share-room-form",
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
    {:ok, view, _html} = live(conn, ~p"/")
    url = "https://example.com/articles/notion-like-embed"

    _html =
      view
      |> form("#share-room-form",
        share: %{
          tweet_url: url
        }
      )
      |> render_submit()

    _html =
      view
      |> element("#share-room-start-create")
      |> render_click()

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#share-room-form",
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

    _html =
      view
      |> element("#share-room-start-create")
      |> render_click()

    _html =
      view
      |> form("#share-room-form",
        share: %{
          title: "",
          tweet_url: url
        }
      )
      |> render_submit()

    assert render(view) =~ "제목을 입력해 주세요"
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

    assert render(view) =~ "유효한 링크를 입력해 주세요"
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
