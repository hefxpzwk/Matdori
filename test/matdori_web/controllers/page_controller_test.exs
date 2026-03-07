defmodule MatdoriWeb.PageControllerTest do
  use MatdoriWeb.ConnCase

  test "GET / renders read-only state for unauthenticated users", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Google 로그인 후 방 만들기"
    assert html =~ "링크를 먼저 입력하세요"
  end
end
