defmodule MatdoriWeb.Plugs.RequireGoogleAuth do
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if logged_in?(conn) do
      conn
    else
      conn
      |> maybe_put_return_to()
      |> redirect(to: "/login")
      |> halt()
    end
  end

  defp logged_in?(conn) do
    uid = get_session(conn, :google_uid)
    is_binary(uid) and uid != ""
  end

  defp maybe_put_return_to(conn) do
    return_to =
      case conn.query_string do
        "" -> conn.request_path
        query -> conn.request_path <> "?" <> query
      end

    put_session(conn, :user_return_to, return_to)
  end
end
