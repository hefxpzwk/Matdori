defmodule MatdoriWeb.AuthControllerTest do
  use MatdoriWeb.ConnCase, async: true

  test "GET /auth/logout clears session and redirects to login", %{conn: conn} do
    conn = init_test_session(conn, %{google_uid: "google-123", display_name: "Tester"})
    conn = get(conn, ~p"/auth/logout")

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "You have been logged out."
    assert get_session(conn, :google_uid) == nil
  end
end
