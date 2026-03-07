defmodule MatdoriWeb.AuthController do
  use MatdoriWeb, :controller

  plug Ueberauth when action in [:request, :callback]

  def login(conn, _params) do
    if logged_in?(conn) do
      redirect(conn, to: ~p"/")
    else
      render(conn, :login)
    end
  end

  def request(conn, _params), do: conn

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    return_to = get_session(conn, :user_return_to) || ~p"/"

    conn
    |> configure_session(renew: true)
    |> put_session(:google_uid, auth.uid)
    |> put_session(:google_email, auth.info.email)
    |> put_session(:google_name, auth.info.name)
    |> put_session(:google_avatar, auth.info.image)
    |> put_session(:session_id, Ecto.UUID.generate())
    |> put_session(:display_name, normalize_display_name(auth.info.name, auth.info.email))
    |> redirect(to: return_to)
  end

  def callback(%{assigns: %{ueberauth_failure: _failure}} = conn, _params) do
    conn
    |> put_flash(:error, "Google 로그인에 실패했습니다. 다시 시도해 주세요.")
    |> redirect(to: ~p"/login")
  end

  def logout(conn, _params) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_flash(:info, "로그아웃되었습니다.")
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
end
