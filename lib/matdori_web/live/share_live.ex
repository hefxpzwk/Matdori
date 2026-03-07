defmodule MatdoriWeb.ShareLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.RateLimiter

  @action_limit 20

  @impl true
  def mount(_params, session, socket) do
    authenticated = logged_in?(session)

    {:ok,
     socket
     |> assign(:session_id, session["session_id"])
     |> assign(:google_uid, session["google_uid"])
     |> assign(:display_name, session["display_name"])
     |> assign(:authenticated, authenticated)
     |> assign(:share_form, empty_share_form())}
  end

  @impl true
  def handle_event("share_room", %{"share" => share_params}, socket) do
    with true <- socket.assigns.authenticated,
         :ok <- RateLimiter.allow?(socket.assigns.session_id, :share_room, @action_limit),
         {:ok, post} <-
           Collab.share_post(
             Map.put(share_params, "google_uid", socket.assigns.google_uid),
             socket.assigns.session_id
           ) do
      {:noreply,
       socket
       |> assign(:share_form, empty_share_form())
       |> put_flash(:info, "새 방이 생성되었습니다")
       |> push_navigate(to: ~p"/rooms/#{post.id}")}
    else
      false ->
        {:noreply,
         socket
         |> put_flash(:error, "로그인한 사용자만 방을 만들 수 있습니다.")
         |> push_navigate(to: ~p"/login")}

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.")}

      {:error, :invalid_title} ->
        {:noreply,
         socket
         |> assign(:share_form, share_form(share_params))
         |> put_flash(:error, "제목을 입력해 주세요")}

      {:error, :invalid_tweet_url} ->
        {:noreply,
         socket
         |> assign(:share_form, share_form(share_params))
         |> put_flash(:error, "유효한 링크를 입력해 주세요")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(:share_form, share_form(share_params))
         |> put_flash(:error, "방을 만들 수 없습니다")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={%{display_name: @display_name, authenticated: @authenticated}}
    >
      <section id="landing-hero" class="rounded-2xl border border-zinc-200 bg-white p-8 shadow-sm">
        <h1 class="text-2xl font-semibold text-zinc-900">좋은 글을 공유하고 함께 생각을 나누세요</h1>
        <p class="mt-2 text-zinc-600">
          제목과 링크를 입력하면 바로 방이 만들어지고, 다른 사람들과 그 글에 대해 이야기할 수 있습니다.
        </p>
      </section>

      <section id="share-create" class="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm">
        <%= if @authenticated do %>
          <.form for={@share_form} id="share-room-form" phx-submit="share_room" class="space-y-2">
            <.input
              id="share-title"
              field={@share_form[:title]}
              type="text"
              label="글 제목"
              placeholder="예: 오늘 꼭 읽어볼 글"
              required
            />
            <.input
              id="share-link-url"
              field={@share_form[:tweet_url]}
              type="url"
              label="링크"
              placeholder="https://example.com/article"
              required
            />
            <button
              id="share-room-submit"
              type="submit"
              class="rounded-lg bg-zinc-900 px-4 py-2 text-sm font-medium text-white"
            >
              방 만들기
            </button>
          </.form>
        <% else %>
          <div id="share-login-required" class="space-y-3">
            <p class="text-sm text-zinc-600">비로그인 사용자는 글 조회만 가능합니다.</p>
            <.link
              id="share-login-link"
              navigate={~p"/login"}
              class="inline-flex rounded-lg border border-zinc-300 px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-50"
            >
              Google 로그인 후 방 만들기
            </.link>
          </div>
        <% end %>
      </section>

      <section id="landing-actions" class="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
        <.link
          id="go-room-list"
          navigate={~p"/rooms"}
          class="inline-flex rounded-lg border border-zinc-300 px-4 py-2 text-sm font-medium text-zinc-700 hover:bg-zinc-50"
        >
          만들어진 방 보러 가기
        </.link>
      </section>
    </Layouts.app>
    """
  end

  defp empty_share_form do
    to_form(%{"title" => "", "tweet_url" => ""}, as: :share)
  end

  defp share_form(params) when is_map(params), do: to_form(params, as: :share)

  defp logged_in?(session) when is_map(session) do
    case session["google_uid"] do
      uid when is_binary(uid) and uid != "" -> true
      _ -> false
    end
  end

  defp logged_in?(_session), do: false
end
