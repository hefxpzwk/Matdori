defmodule MatdoriWeb.Plugs.Identity do
  import Plug.Conn

  alias Matdori.Collab

  @colors [
    "#ef4444",
    "#f97316",
    "#eab308",
    "#22c55e",
    "#06b6d4",
    "#3b82f6",
    "#8b5cf6",
    "#ec4899"
  ]

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> ensure_session_id()
    |> ensure_display_name()
    |> ensure_color()
  end

  defp ensure_session_id(conn) do
    case get_session(conn, :session_id) do
      nil -> put_session(conn, :session_id, Ecto.UUID.generate())
      _ -> conn
    end
  end

  defp ensure_display_name(conn) do
    profile_name =
      conn
      |> get_session(:google_uid)
      |> profile_display_name()

    display_name =
      profile_name ||
        get_session(conn, :display_name) ||
        get_session(conn, :google_name) ||
        get_session(conn, :google_email)

    normalized = normalize_display_name(display_name)
    put_session(conn, :display_name, normalized)
  end

  defp profile_display_name(google_uid) when is_binary(google_uid) and google_uid != "" do
    case Collab.get_profile_by_google_uid(google_uid) do
      %{display_name: name} when is_binary(name) and name != "" -> name
      _ -> nil
    end
  end

  defp profile_display_name(_google_uid), do: nil

  defp ensure_color(conn) do
    case get_session(conn, :color) do
      nil -> put_session(conn, :color, Enum.random(@colors))
      _ -> conn
    end
  end

  defp normalize_display_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> "Google User"
      value -> String.slice(value, 0, 30)
    end
  end

  defp normalize_display_name(_), do: "Google User"
end
