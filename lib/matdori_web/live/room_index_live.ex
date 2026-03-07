defmodule MatdoriWeb.RoomIndexLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.Embed

  @embed_filters ~w(all embedded preview)
  @sort_options ~w(latest likes views)

  @impl true
  def mount(_params, session, socket) do
    authenticated = logged_in?(session)

    {:ok,
     socket
     |> assign(:posts, [])
     |> assign(:display_name, session["display_name"])
     |> assign(:email, session["google_email"])
     |> assign(:avatar_url, session["google_avatar"])
     |> assign(:authenticated, authenticated)
     |> assign(:embed_filter, "all")
     |> assign(:sort, "latest")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    embed_filter = params |> Map.get("embed", "all") |> normalize_embed_filter()
    sort = params |> Map.get("sort", "latest") |> normalize_sort()

    posts =
      Collab.list_posts(200, sort: sort)
      |> filter_embed(embed_filter)

    {:noreply,
     socket
     |> assign(:embed_filter, embed_filter)
     |> assign(:sort, sort)
     |> assign(:posts, posts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={
        %{
          display_name: @display_name,
          email: @email,
          avatar_url: @avatar_url,
          authenticated: @authenticated
        }
      }
    >
      <section id="room-list" class="mat-surface space-y-4 p-6 sm:p-8">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <p class="text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
              Community Rooms
            </p>
            <h1 class="mt-1 text-2xl font-black tracking-tight text-slate-900">만들어진 방 목록</h1>
          </div>

          <%= if @authenticated do %>
            <.link
              id="go-share-page"
              navigate={~p"/"}
              class="mat-btn-primary"
            >
              새 방 만들기
            </.link>
          <% else %>
            <.link
              id="go-login-page"
              navigate={~p"/login"}
              class="mat-btn-secondary"
            >
              로그인
            </.link>
          <% end %>
        </div>

        <div
          id="room-list-controls"
          class="mat-panel grid gap-4 p-4 sm:grid-cols-2"
        >
          <div id="room-items" class="space-y-2">
            <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">임베드 필터</p>
            <div class="flex flex-wrap gap-2">
              <.link
                id="room-filter-all"
                patch={room_list_path("all", @sort)}
                class={control_link_class(@embed_filter == "all")}
              >
                전체
              </.link>
              <.link
                id="room-filter-embedded"
                patch={room_list_path("embedded", @sort)}
                class={control_link_class(@embed_filter == "embedded")}
              >
                임베드 가능
              </.link>
              <.link
                id="room-filter-preview"
                patch={room_list_path("preview", @sort)}
                class={control_link_class(@embed_filter == "preview")}
              >
                미리보기만
              </.link>
            </div>
          </div>

          <div class="space-y-2">
            <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">정렬</p>
            <div class="flex flex-wrap gap-2">
              <.link
                id="room-sort-latest"
                patch={room_list_path(@embed_filter, "latest")}
                class={control_link_class(@sort == "latest")}
              >
                최신순
              </.link>
              <.link
                id="room-sort-likes"
                patch={room_list_path(@embed_filter, "likes")}
                class={control_link_class(@sort == "likes")}
              >
                좋아요순
              </.link>
              <.link
                id="room-sort-views"
                patch={room_list_path(@embed_filter, "views")}
                class={control_link_class(@sort == "views")}
              >
                조회순
              </.link>
            </div>
          </div>
        </div>

        <%= if @posts == [] do %>
          <div
            id="room-list-empty"
            class="mat-panel p-5 text-sm text-slate-600"
          >
            아직 만들어진 방이 없습니다. 메인 페이지에서 첫 방을 만들어 보세요.
          </div>
        <% else %>
          <div class="space-y-3">
            <%= for post <- @posts do %>
              <.link
                id={"room-item-#{post.id}"}
                navigate={~p"/rooms/#{post.id}"}
                class="mat-card group block p-4"
              >
                <div class="flex items-center gap-2.5">
                  <p class="truncate text-sm font-bold text-slate-900">{display_title(post)}</p>
                  <span
                    id={"room-status-#{post.id}"}
                    class="mat-pill px-2.5 py-1 text-[11px]"
                  >
                    {embed_status_label(post)}
                  </span>
                </div>
                <p class="mt-1.5 truncate text-xs text-slate-500">{post.tweet_url}</p>
                <div class="mt-3 flex flex-wrap items-center gap-2 text-xs text-slate-700">
                  <span id={"room-like-count-#{post.id}"}>좋아요 {post.like_count}</span>
                  <span id={"room-dislike-count-#{post.id}"}>싫어요 {post.dislike_count}</span>
                  <span id={"room-view-count-#{post.id}"}>조회수 {post.view_count}</span>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp display_title(post) do
    case String.trim(post.title || "") do
      "" -> "제목 없는 공유"
      title -> title
    end
  end

  defp normalize_embed_filter(filter) when filter in @embed_filters, do: filter
  defp normalize_embed_filter(_filter), do: "all"

  defp normalize_sort(sort) when sort in @sort_options, do: sort
  defp normalize_sort(_sort), do: "latest"

  defp filter_embed(posts, "all"), do: posts

  defp filter_embed(posts, "embedded") do
    Enum.filter(posts, &(Embed.classify(&1.tweet_url).mode == :native_embed))
  end

  defp filter_embed(posts, "preview") do
    Enum.filter(posts, &(Embed.classify(&1.tweet_url).mode == :preview_only))
  end

  defp room_list_path(embed_filter, sort) do
    ~p"/rooms?#{%{embed: embed_filter, sort: sort}}"
  end

  defp control_link_class(active?) do
    [
      "mat-control-chip",
      if(active?,
        do: "is-active",
        else: nil
      )
    ]
  end

  defp embed_status_label(post), do: post.tweet_url |> Embed.classify() |> Embed.status_label()

  defp logged_in?(session) when is_map(session) do
    case session["google_uid"] do
      uid when is_binary(uid) and uid != "" -> true
      _ -> false
    end
  end

  defp logged_in?(_session), do: false
end
