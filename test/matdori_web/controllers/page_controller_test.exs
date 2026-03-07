defmodule MatdoriWeb.PageControllerTest do
  use MatdoriWeb.ConnCase

  test "GET / renders read-only state for unauthenticated users", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "좋은 글을 공유하고 함께 생각을 나누세요"
    assert html =~ "비로그인 사용자는 글 조회만 가능합니다"
  end
end
