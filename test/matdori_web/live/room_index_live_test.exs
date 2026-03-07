defmodule MatdoriWeb.RoomIndexLiveTest do
  use MatdoriWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Matdori.Collab
  alias Matdori.Collab.Post
  alias Matdori.Repo

  test "unauthenticated users can access room index", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rooms")

    assert has_element?(view, "#room-list")
    assert has_element?(view, "#go-login-page")
  end

  test "room index shows created rooms", %{conn: conn} do
    conn = google_auth_conn(conn)
    id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, post} =
             Collab.share_post(
               %{
                 "title" => "인덱스에서 보이는 제목",
                 "tweet_url" => "https://x.com/room_list_user/status/#{id}"
               },
               "room-index-test"
             )

    assert {:ok, _} = Collab.toggle_reaction(post.id, "room-index-like-1", "like")
    assert {:ok, _} = Collab.toggle_reaction(post.id, "room-index-like-2", "like")
    assert {:ok, _} = Collab.toggle_reaction(post.id, "room-index-dislike-1", "dislike")

    {:ok, view, _html} = live(conn, ~p"/rooms")

    assert has_element?(view, "#room-item-#{post.id}")
    assert has_element?(view, "#room-status-#{post.id}")
    assert has_element?(view, "#room-like-count-#{post.id}", "좋아요 2")
    assert has_element?(view, "#room-dislike-count-#{post.id}", "싫어요 1")
    assert has_element?(view, "#room-view-count-#{post.id}", "조회수 0")
    assert render(view) =~ "인덱스에서 보이는 제목"
    assert render(view) =~ "임베드 가능"
  end

  test "room index filters embedded and preview rooms", %{conn: conn} do
    conn = google_auth_conn(conn)
    x_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, x_post} =
             Collab.share_post(
               %{"title" => "임베드 방", "tweet_url" => "https://x.com/filter_user/status/#{x_id}"},
               "room-index-filter-x"
             )

    assert {:ok, preview_post} =
             Collab.share_post(
               %{"title" => "미리보기 방", "tweet_url" => "https://example.com/filter-preview"},
               "room-index-filter-preview"
             )

    {:ok, view, _html} = live(conn, ~p"/rooms")

    assert has_element?(view, "#room-item-#{x_post.id}")
    assert has_element?(view, "#room-item-#{preview_post.id}")

    view |> element("#room-filter-embedded") |> render_click()

    assert has_element?(view, "#room-item-#{x_post.id}")
    refute has_element?(view, "#room-item-#{preview_post.id}")

    view |> element("#room-filter-preview") |> render_click()

    assert has_element?(view, "#room-item-#{preview_post.id}")
    refute has_element?(view, "#room-item-#{x_post.id}")
  end

  test "room index sorts by likes and views", %{conn: conn} do
    conn = google_auth_conn(conn)
    first_id = Integer.to_string(System.unique_integer([:positive]))
    second_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, first} =
             Collab.share_post(
               %{"title" => "첫번째 방", "tweet_url" => "https://x.com/sort_user/status/#{first_id}"},
               "room-index-sort-1"
             )

    assert {:ok, second} =
             Collab.share_post(
               %{
                 "title" => "두번째 방",
                 "tweet_url" => "https://x.com/sort_user/status/#{second_id}"
               },
               "room-index-sort-2"
             )

    assert {:ok, _} = Collab.toggle_reaction(first.id, "room-index-sort-like-1", "like")
    assert {:ok, _} = Collab.toggle_reaction(first.id, "room-index-sort-like-2", "like")
    assert {:ok, _} = Collab.toggle_reaction(second.id, "room-index-sort-like-3", "like")

    assert :ok = Collab.register_view(second.id, "room-index-sort-view-1")
    assert :ok = Collab.register_view(second.id, "room-index-sort-view-2")
    assert :ok = Collab.register_view(first.id, "room-index-sort-view-3")

    {:ok, view, _html} = live(conn, ~p"/rooms")

    view |> element("#room-sort-likes") |> render_click()
    likes_html = render(view)

    assert html_position(likes_html, ~s(id="room-item-#{first.id}")) <
             html_position(likes_html, ~s(id="room-item-#{second.id}"))

    view |> element("#room-sort-views") |> render_click()
    views_html = render(view)

    assert html_position(views_html, ~s(id="room-item-#{second.id}")) <
             html_position(views_html, ~s(id="room-item-#{first.id}"))
  end

  test "room index latest sort uses room recency not tweet posted time", %{conn: conn} do
    conn = google_auth_conn(conn)
    older_id = Integer.to_string(System.unique_integer([:positive]))
    newer_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, older} =
             Collab.share_post(
               %{
                 "title" => "먼저 만든 방",
                 "tweet_url" => "https://x.com/latest_user/status/#{older_id}"
               },
               "room-index-latest-1"
             )

    assert {:ok, newer} =
             Collab.share_post(
               %{
                 "title" => "나중에 만든 방",
                 "tweet_url" => "https://x.com/latest_user/status/#{newer_id}"
               },
               "room-index-latest-2"
             )

    old_tweet_time =
      DateTime.utc_now() |> DateTime.add(-3650, :day) |> DateTime.truncate(:microsecond)

    assert %Post{} =
             newer |> Ecto.Changeset.change(tweet_posted_at: old_tweet_time) |> Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/rooms")
    latest_html = render(view)

    assert html_position(latest_html, ~s(id="room-item-#{newer.id}")) <
             html_position(latest_html, ~s(id="room-item-#{older.id}"))
  end

  test "likes and views sort fall back to latest on ties", %{conn: conn} do
    conn = google_auth_conn(conn)
    older_id = Integer.to_string(System.unique_integer([:positive]))
    newer_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, older} =
             Collab.share_post(
               %{
                 "title" => "tie-older",
                 "tweet_url" => "https://x.com/tie_user/status/#{older_id}"
               },
               "room-index-tie-1"
             )

    assert {:ok, newer} =
             Collab.share_post(
               %{
                 "title" => "tie-newer",
                 "tweet_url" => "https://x.com/tie_user/status/#{newer_id}"
               },
               "room-index-tie-2"
             )

    assert {:ok, _} = Collab.toggle_reaction(older.id, "room-index-tie-like-older", "like")
    assert {:ok, _} = Collab.toggle_reaction(newer.id, "room-index-tie-like-newer", "like")

    assert :ok = Collab.register_view(older.id, "room-index-tie-view-older")
    assert :ok = Collab.register_view(newer.id, "room-index-tie-view-newer")

    {:ok, view, _html} = live(conn, ~p"/rooms")

    view |> element("#room-sort-likes") |> render_click()
    likes_html = render(view)

    assert html_position(likes_html, ~s(id="room-item-#{newer.id}")) <
             html_position(likes_html, ~s(id="room-item-#{older.id}"))

    view |> element("#room-sort-views") |> render_click()
    views_html = render(view)

    assert html_position(views_html, ~s(id="room-item-#{newer.id}")) <
             html_position(views_html, ~s(id="room-item-#{older.id}"))
  end

  defp html_position(html, needle) do
    case :binary.match(html, needle) do
      {index, _length} -> index
      :nomatch -> flunk("Expected to find #{needle} in HTML")
    end
  end
end
