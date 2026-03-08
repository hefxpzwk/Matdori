defmodule MatdoriWeb.PageControllerTest do
  use MatdoriWeb.ConnCase

  test "GET / renders read-only state for unauthenticated users", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Sign in with Google to create a room"
    assert html =~ "Enter a link first"
  end
end
