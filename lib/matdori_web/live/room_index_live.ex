defmodule MatdoriWeb.RoomIndexLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.Embed

  @embed_filters ~w(all embedded preview)
  @sort_options ~w(latest likes views)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:posts, [])
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
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section
        id="room-list"
        class="space-y-3 rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm"
      >
        <div class="flex items-center justify-between">
          <h1 class="text-xl font-semibold text-zinc-900">만들어진 방 목록</h1>
          <.link
            id="go-share-page"
            navigate={~p"/"}
            class="rounded-lg border border-zinc-300 px-3 py-1 text-sm text-zinc-700 hover:bg-zinc-50"
          >
            새 방 만들기
          </.link>
        </div>

        <div
          id="room-list-controls"
          class="grid gap-3 rounded-lg border border-zinc-200 bg-zinc-50 p-3 sm:grid-cols-2"
        >
          <div id="room-items" class="space-y-2">
            <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500">임베드 필터</p>
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
            <p class="text-xs font-semibold uppercase tracking-wide text-zinc-500">정렬</p>
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
            class="rounded-lg border border-zinc-200 bg-zinc-50 p-4 text-sm text-zinc-600"
          >
            아직 만들어진 방이 없습니다. 메인 페이지에서 첫 방을 만들어 보세요.
          </div>
        <% else %>
          <div class="space-y-2">
            <%= for post <- @posts do %>
              <.link
                id={"room-item-#{post.id}"}
                navigate={~p"/rooms/#{post.id}"}
                class="block rounded-lg border border-zinc-200 p-3 hover:bg-zinc-50"
              >
                <div class="flex items-center gap-2">
                  <p class="truncate text-sm font-medium text-zinc-900">{display_title(post)}</p>
                  <span
                    id={"room-status-#{post.id}"}
                    class="rounded-full border border-zinc-300 px-2 py-0.5 text-[11px] font-medium text-zinc-600"
                  >
                    {embed_status_label(post)}
                  </span>
                </div>
                <p class="mt-1 truncate text-xs text-zinc-500">{post.tweet_url}</p>
                <div class="mt-2 flex items-center gap-3 text-xs text-zinc-600">
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
      "rounded-full border px-2.5 py-1 text-xs font-medium transition",
      if(active?,
        do: "border-zinc-700 bg-zinc-900 text-white",
        else: "border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-100"
      )
    ]
  end

  defp embed_status_label(post), do: post.tweet_url |> Embed.classify() |> Embed.status_label()
end
