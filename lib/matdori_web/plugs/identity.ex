defmodule MatdoriWeb.Plugs.Identity do
  import Plug.Conn

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

  @adjectives ~w(Bright Swift Warm Calm Bold Quiet Focused Lively)
  @animals ~w(Fox Whale Sparrow Koala Raven Otter Lynx Panda)

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
    case get_session(conn, :display_name) do
      nil ->
        name = "#{Enum.random(@adjectives)} #{Enum.random(@animals)}"
        put_session(conn, :display_name, name)

      _ ->
        conn
    end
  end

  defp ensure_color(conn) do
    case get_session(conn, :color) do
      nil -> put_session(conn, :color, Enum.random(@colors))
      _ -> conn
    end
  end
end
