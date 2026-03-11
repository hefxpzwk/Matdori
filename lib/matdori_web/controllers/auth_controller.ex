defmodule MatdoriWeb.AuthController do
  use MatdoriWeb, :controller

  alias Matdori.Collab

  plug Ueberauth when action in [:request, :callback]

  def login(conn, _params) do
    if logged_in?(conn) do
      redirect(conn, to: ~p"/")
    else
      render(conn, :login)
    end
  end

  def request(conn, _params) do
    if conn.halted or conn.state != :unset do
      conn
    else
      conn
      |> put_flash(:error, "Unsupported login method.")
      |> redirect(to: ~p"/login")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    return_to = get_session(conn, :user_return_to) || ~p"/"
    display_name = profile_or_google_display_name(auth.uid, auth.info.name, auth.info.email)
    color = profile_or_default_color(auth.uid)

    _ =
      Collab.upsert_profile_by_google_uid(auth.uid, %{
        display_name: display_name,
        color: color,
        avatar_url: auth.info.image
      })

    conn
    |> configure_session(renew: true)
    |> put_session(:google_uid, auth.uid)
    |> put_session(:google_email, auth.info.email)
    |> put_session(:google_name, auth.info.name)
    |> put_session(:google_avatar, auth.info.image)
    |> put_session(:session_id, Ecto.UUID.generate())
    |> put_session(:display_name, display_name)
    |> put_session(:color, color)
    |> redirect(to: return_to)
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Google sign-in failed. Please try again.")
    |> redirect(to: ~p"/login")
  end

  def logout(conn, _params) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/login")
  end

  defp logged_in?(conn) do
    uid = get_session(conn, :google_uid)
    is_binary(uid) and uid != ""
  end

  defp normalize_display_name(name, _email) when is_binary(name) and name != "" do
    name
    |> String.trim()
    |> String.slice(0, 30)
  end

  defp normalize_display_name(_name, email) when is_binary(email) and email != "" do
    email
    |> String.trim()
    |> String.slice(0, 30)
  end

  defp normalize_display_name(_name, _email), do: "Google User"

  defp profile_or_google_display_name(google_uid, google_name, google_email) do
    case Collab.get_profile_by_google_uid(google_uid) do
      %{display_name: name} when is_binary(name) and name != "" ->
        name

      _ ->
        normalize_display_name(google_name, google_email)
    end
  end

  defp profile_or_default_color(google_uid) do
    case Collab.get_profile_by_google_uid(google_uid) do
      %{color: color} when is_binary(color) and color != "" -> color
      _ -> "#3b82f6"
    end
  end
end
