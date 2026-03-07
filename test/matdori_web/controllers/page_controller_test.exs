defmodule MatdoriWeb.PageControllerTest do
  use MatdoriWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "좋은 글을 공유하고 함께 생각을 나누세요"
  end
end
