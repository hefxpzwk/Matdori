defmodule MatdoriWeb.PageController do
  use MatdoriWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
