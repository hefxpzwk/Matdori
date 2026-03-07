defmodule MatdoriWeb.ShareLiveTest do
  use MatdoriWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Matdori.Collab

  test "users can create room with title and link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    id = Integer.to_string(System.unique_integer([:positive]))

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#share-room-form",
               share: %{
                 title: "같이 읽고 싶은 글",
                 tweet_url: "https://x.com/community_user/status/#{id}"
               }
             )
             |> render_submit()

    assert to =~ ~r|^/rooms/\d+$|

    latest = Collab.get_latest_post_with_versions()
    assert latest.title == "같이 읽고 싶은 글"
    assert latest.tweet_id == id
  end

  test "users can create room from generic web link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: to}}} =
             view
             |> form("#share-room-form",
               share: %{
                 title: "블로그 공유",
                 tweet_url: "https://example.com/articles/notion-like-embed"
               }
             )
             |> render_submit()

    assert to =~ ~r|^/rooms/\d+$|

    latest = Collab.get_latest_post_with_versions()
    assert latest.title == "블로그 공유"
    assert latest.tweet_id =~ "url-"
  end

  test "title is required when creating room", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    id = Integer.to_string(System.unique_integer([:positive]))

    _html =
      view
      |> form("#share-room-form",
        share: %{
          title: "",
          tweet_url: "https://x.com/community_user/status/#{id}"
        }
      )
      |> render_submit()

    assert render(view) =~ "제목을 입력해 주세요"
  end

  test "invalid url shows validation feedback", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    _html =
      view
      |> form("#share-room-form",
        share: %{
          title: "잘못된 링크",
          tweet_url: "not-a-url"
        }
      )
      |> render_submit()

    assert render(view) =~ "유효한 링크를 입력해 주세요"
  end
end
