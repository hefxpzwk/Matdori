defmodule MatdoriWeb.RoomIndexLiveTest do
  use MatdoriWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Matdori.Collab

  test "room index shows created rooms", %{conn: conn} do
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

  defp html_position(html, needle) do
    case :binary.match(html, needle) do
      {index, _length} -> index
      :nomatch -> flunk("Expected to find #{needle} in HTML")
    end
  end
end
