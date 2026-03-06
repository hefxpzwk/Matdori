defmodule MatdoriWeb.AdminReportsLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:session_id, session["session_id"])
     |> assign(:authenticated, false)
     |> assign(:reports, [])}
  end

  @impl true
  def handle_event("verify_token", %{"admin" => %{"token" => token}}, socket) do
    with :ok <- Matdori.RateLimiter.allow?(socket.assigns.session_id, :admin_verify_reports, 20) do
      if token_valid?(token) do
        {:noreply,
         socket |> assign(:authenticated, true) |> assign(:reports, Collab.list_reports())}
      else
        {:noreply, put_flash(socket, :error, "관리자 토큰이 올바르지 않습니다")}
      end
    else
      {:error, :rate_limited} -> {:noreply, put_flash(socket, :error, "시도 횟수가 너무 많습니다")}
    end
  end

  def handle_event("takedown_post", %{"post_id" => post_id}, socket) do
    if socket.assigns.authenticated do
      case Integer.parse(post_id) do
        {parsed, ""} ->
          _ = Collab.takedown_post(parsed, "report_review_takedown")

          {:noreply,
           socket
           |> assign(:reports, Collab.list_reports())
           |> put_flash(:info, "포스트를 숨겼습니다")}

        _ ->
          {:noreply, put_flash(socket, :error, "잘못된 포스트 ID입니다")}
      end
    else
      {:noreply, put_flash(socket, :error, "먼저 인증해 주세요")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section id="admin-reports" class="space-y-4">
        <h1 class="text-xl font-semibold">관리자 · 신고 내역</h1>

        <%= if !@authenticated do %>
          <form
            id="admin-reports-token-form"
            phx-submit="verify_token"
            class="rounded-xl border border-zinc-200 bg-white p-4"
          >
            <label for="admin-reports-token" class="mb-1 block text-sm text-zinc-700">
              관리자 토큰
            </label>
            <input
              id="admin-reports-token"
              name="admin[token]"
              type="password"
              class="w-full rounded-md border border-zinc-300 px-3 py-2"
            />
            <button
              id="admin-reports-token-submit"
              type="submit"
              class="rounded-lg border border-zinc-300 px-3 py-1 text-sm"
            >
              잠금 해제
            </button>
          </form>
        <% else %>
          <div class="rounded-xl border border-zinc-200 bg-white p-4">
            <p class="text-sm text-zinc-600">총 신고 수: {length(@reports)}</p>
            <ul id="reports-list" class="mt-2 space-y-2">
              <li
                :for={report <- @reports}
                id={"report-#{report.id}"}
                class="rounded-md border border-zinc-200 p-2 text-sm"
              >
                <p><span class="font-medium">신고자:</span> {report.display_name}</p>
                <p><span class="font-medium">사유:</span> {report.reason}</p>
                <p><span class="font-medium">트윗 URL:</span> {report.post.tweet_url}</p>
                <button
                  id={"takedown-post-#{report.post_id}"}
                  phx-click="takedown_post"
                  phx-value-post_id={report.post_id}
                  class="mt-1 rounded border border-rose-300 px-2 py-1 text-xs text-rose-700"
                >
                  이 포스트 숨김 처리
                </button>
              </li>
            </ul>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp admin_token do
    case System.get_env("ADMIN_TOKEN") do
      nil -> fallback_admin_token()
      "" -> fallback_admin_token()
      token -> token
    end
  end

  defp fallback_admin_token do
    if Application.get_env(:matdori, :dev_routes) do
      "dev-admin-token"
    else
      "__missing_admin_token__"
    end
  end

  defp token_valid?(token) when is_binary(token) do
    expected = admin_token()

    if byte_size(token) == byte_size(expected) do
      Plug.Crypto.secure_compare(token, expected)
    else
      false
    end
  end
end
