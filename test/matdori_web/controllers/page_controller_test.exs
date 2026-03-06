defmodule MatdoriWeb.PageControllerTest do
  use MatdoriWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "오늘의 X 게시글을 실시간으로 함께 토론하는 방입니다"
  end
end
