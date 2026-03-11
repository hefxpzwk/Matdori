defmodule MatdoriWeb.UserProfileLiveTest do
  use MatdoriWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Matdori.Collab

  test "public user profile page renders profile and room links", %{conn: conn} do
    google_uid = "public-profile-user"

    assert {:ok, created_post} =
             Collab.share_post(
               %{
                 "title" => "프로필 공개 방",
                 "tweet_url" =>
                   "https://x.com/public_profile_created/status/#{System.unique_integer([:positive])}",
                 "google_uid" => google_uid
               },
               "public-profile-created"
             )

    assert {:ok, _profile} =
             Collab.upsert_profile_by_google_uid(google_uid, %{
               display_name: "프로필 유저",
               interests: ["리뷰", "협업"],
               color: "#0ea5e9"
             })

    {:ok, view, _html} = live(conn, ~p"/users/#{google_uid}")

    assert has_element?(view, "#my-page")
    assert has_element?(view, "#my-profile-name", "프로필 유저")
    assert has_element?(view, "#my-profile-interest")
    assert has_element?(view, "#my-tab-created")
    assert has_element?(view, "#my-tab-active")
    assert has_element?(view, "#my-tab-liked")
    assert has_element?(view, "#my-created-room-#{created_post.id}")
    assert has_element?(view, "#my-created-like-count-#{created_post.id}")
    assert has_element?(view, "#my-created-dislike-count-#{created_post.id}")
    assert has_element?(view, "#my-created-view-count-#{created_post.id}")
    assert has_element?(view, "#my-created-live-count-#{created_post.id}")
    assert has_element?(view, "#my-created-comment-count-#{created_post.id}")
    refute has_element?(view, "#user-profile-my-page-link")
  end

  test "user profile active tab shows rooms with comments or highlights", %{conn: conn} do
    google_uid = "active-profile-user"

    assert {:ok, highlighted_post} =
             Collab.share_post(
               %{
                 "title" => "하이라이트 활동 방",
                 "tweet_url" =>
                   "https://x.com/public_profile_active_highlight/status/#{System.unique_integer([:positive])}",
                 "google_uid" => "another-user"
               },
               "public-profile-active-highlight-owner"
             )

    assert {:ok, commented_post} =
             Collab.share_post(
               %{
                 "title" => "댓글 활동 방",
                 "tweet_url" =>
                   "https://x.com/public_profile_active_comment/status/#{System.unique_integer([:positive])}",
                 "google_uid" => "another-user-2"
               },
               "public-profile-active-comment-owner"
             )

    snapshot = highlighted_post.current_snapshot

    assert {:ok, _highlight} =
             Collab.create_highlight(snapshot, %{
               "session_id" => "public-profile-active-highlight-session",
               "google_uid" => google_uid,
               "display_name" => "액티브 유저",
               "color" => "#3b82f6",
               "quote_exact" => "This",
               "quote_prefix" => "",
               "quote_suffix" => "",
               "start_g" => 0,
               "end_g" => 4
             })

    assert {:ok, _comment} =
             Collab.create_room_comment(commented_post.id, %{
               "session_id" => "public-profile-active-comment-session",
               "google_uid" => google_uid,
               "display_name" => "액티브 유저",
               "color" => "#3b82f6",
               "body" => "좋은 방이네요"
             })

    assert {:ok, _profile} =
             Collab.upsert_profile_by_google_uid(google_uid, %{
               display_name: "액티브 유저",
               interests: ["리뷰"],
               color: "#0ea5e9"
             })

    {:ok, view, _html} = live(conn, ~p"/users/#{google_uid}")

    _html = view |> element("#my-tab-active") |> render_click()

    assert has_element?(view, "#my-active-room-#{highlighted_post.id}")
    assert has_element?(view, "#my-active-room-#{commented_post.id}")
  end

  test "user profile page shows my-page shortcut for owner", %{conn: conn} do
    google_uid = "owner-profile-user"
    conn = google_auth_conn(conn, %{"google_uid" => google_uid})

    assert {:ok, _profile} =
             Collab.upsert_profile_by_google_uid(google_uid, %{
               display_name: "오너 유저",
               interests: [],
               color: "#14b8a6"
             })

    {:ok, view, _html} = live(conn, ~p"/users/#{google_uid}")

    assert has_element?(view, "#user-profile-my-page-link[href='/me']")
  end
end
