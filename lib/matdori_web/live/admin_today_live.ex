defmodule MatdoriWeb.AdminTodayLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:session_id, session["session_id"])
     |> assign(:authenticated, false)
     |> assign(:post, Collab.get_today_post_with_versions())}
  end

  @impl true
  def handle_event("verify_token", %{"admin" => %{"token" => token}}, socket) do
    with :ok <- Matdori.RateLimiter.allow?(socket.assigns.session_id, :admin_verify, 20) do
      if token_valid?(token) do
        {:noreply, assign(socket, :authenticated, true)}
      else
        {:noreply, put_flash(socket, :error, "관리자 토큰이 올바르지 않습니다")}
      end
    else
      {:error, :rate_limited} -> {:noreply, put_flash(socket, :error, "시도 횟수가 너무 많습니다")}
    end
  end

  def handle_event("create_today", %{"post" => params}, socket) do
    if socket.assigns.authenticated do
      case Collab.upsert_today_post(params, socket.assigns.session_id) do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(:post, Collab.get_today_post_with_versions())
           |> put_flash(:info, "오늘의 포스트를 업데이트했습니다")}

        {:error, :empty_snapshot} ->
          {:noreply, put_flash(socket, :error, "스냅샷 텍스트는 비워둘 수 없습니다")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "포스트 저장에 실패했습니다")}
      end
    else
      {:noreply, put_flash(socket, :error, "먼저 인증해 주세요")}
    end
  end

  def handle_event("takedown", _params, socket) do
    if socket.assigns.authenticated do
      Collab.takedown_today_post("admin_takedown")

      {:noreply,
       socket
       |> assign(:post, Collab.get_today_post_with_versions())
       |> put_flash(:info, "방 콘텐츠를 숨겼습니다")}
    else
      {:noreply, put_flash(socket, :error, "먼저 인증해 주세요")}
    end
  end

  def handle_event("restore", _params, socket) do
    if socket.assigns.authenticated do
      Collab.restore_today_post()

      {:noreply,
       socket
       |> assign(:post, Collab.get_today_post_with_versions())
       |> put_flash(:info, "방 콘텐츠를 복원했습니다")}
    else
      {:noreply, put_flash(socket, :error, "먼저 인증해 주세요")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section id="admin-today" class="space-y-4">
        <h1 class="text-xl font-semibold">관리자 · 오늘의 포스트</h1>

        <%= if !@authenticated do %>
          <form
            id="admin-token-form"
            phx-submit="verify_token"
            class="rounded-xl border border-zinc-200 bg-white p-4"
          >
            <label for="admin-token" class="mb-1 block text-sm text-zinc-700">관리자 토큰</label>
            <input
              id="admin-token"
              name="admin[token]"
              type="password"
              class="w-full rounded-md border border-zinc-300 px-3 py-2"
            />
            <button
              id="admin-token-submit"
              type="submit"
              class="rounded-lg border border-zinc-300 px-3 py-1 text-sm"
            >
              잠금 해제
            </button>
          </form>
        <% else %>
          <form
            id="admin-create-form"
            phx-submit="create_today"
            class="rounded-xl border border-zinc-200 bg-white p-4"
          >
            <label for="tweet-url" class="mb-1 block text-sm text-zinc-700">X 게시글 URL</label>
            <input
              id="tweet-url"
              name="post[tweet_url]"
              type="url"
              required
              class="w-full rounded-md border border-zinc-300 px-3 py-2"
              placeholder="https://x.com/.../status/..."
            />
            <label for="snapshot-text" class="mb-1 mt-3 block text-sm text-zinc-700">
              스냅샷 텍스트
            </label>
            <textarea
              id="snapshot-text"
              name="post[snapshot_text]"
              required
              rows="8"
              class="w-full rounded-md border border-zinc-300 px-3 py-2"
              placeholder="사용자들이 하이라이트/댓글을 달 텍스트를 붙여넣어 주세요"
            ></textarea>
            <button
              id="admin-save"
              type="submit"
              class="mt-2 rounded-lg border border-zinc-300 px-3 py-1 text-sm"
            >
              오늘의 포스트 저장
            </button>
          </form>

          <div class="flex gap-2">
            <button
              id="admin-takedown"
              phx-click="takedown"
              class="rounded-lg border border-rose-300 px-3 py-1 text-sm text-rose-700"
            >
              숨김 처리
            </button>
            <button
              id="admin-restore"
              phx-click="restore"
              class="rounded-lg border border-emerald-300 px-3 py-1 text-sm text-emerald-700"
            >
              복원
            </button>
          </div>

          <%= if @post do %>
            <div id="snapshot-versions" class="rounded-xl border border-zinc-200 bg-white p-4">
              <p class="text-sm text-zinc-700">현재 URL: {@post.tweet_url}</p>
              <p class="text-sm text-zinc-700">숨김 상태: {to_string(@post.hidden)}</p>
              <ul class="mt-2 list-disc pl-5 text-sm text-zinc-600">
                <li :for={snapshot <- @post.snapshots}>
                  v{snapshot.version} · 등록 시각 {snapshot.inserted_at}
                </li>
              </ul>
            </div>
          <% end %>
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
