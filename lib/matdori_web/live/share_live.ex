defmodule MatdoriWeb.ShareLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.RateLimiter
  alias MatdoriWeb.Presence

  @action_limit 20
  @feed_limit 60
  @feed_refresh_ms 6_000

  @impl true
  def mount(_params, session, socket) do
    authenticated = logged_in?(session)

    {:ok,
     socket
     |> assign(:session_id, session["session_id"])
     |> assign(:google_uid, session["google_uid"])
     |> assign(:display_name, session["display_name"])
     |> assign(:email, session["google_email"])
     |> assign(:avatar_url, session["google_avatar"])
     |> assign(:authenticated, authenticated)
     |> assign(:composer_mode, :search)
     |> assign(:search_status, :idle)
     |> assign(:feed_sort, "latest")
     |> assign(:feed_posts, [])
     |> assign(:active_counts, %{})
     |> assign(:feed_loaded?, false)
     |> assign(:share_form, empty_share_form())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sort = params |> Map.get("sort", socket.assigns.feed_sort) |> normalize_feed_sort()

    socket =
      socket
      |> assign_feed(sort)
      |> maybe_schedule_feed_refresh()

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_link", %{"share" => share_params}, socket) do
    params = normalized_share_params(share_params)
    tweet_url = String.trim(params["tweet_url"])

    cond do
      tweet_url == "" ->
        {:noreply,
         socket
         |> assign(:share_form, share_form(params))
         |> assign(:composer_mode, :search)
         |> assign(:search_status, :idle)
         |> put_flash(:error, "링크를 입력해 주세요")}

      true ->
        case Collab.find_post_by_url(tweet_url) do
          {:ok, post} ->
            {:noreply,
             socket
             |> assign(:share_form, share_form(params))
             |> assign(:composer_mode, :search)
             |> assign(:search_status, :found)
             |> push_navigate(to: ~p"/rooms/#{post.id}")}

          :not_found ->
            {:noreply,
             socket
             |> assign(:share_form, share_form(params))
             |> assign(:composer_mode, :search)
             |> assign(:search_status, :not_found)
             |> put_flash(:info, "기존 방이 없어 새 방을 만들 수 있습니다")}

          {:error, :invalid_tweet_url} ->
            {:noreply,
             socket
             |> assign(:share_form, share_form(params))
             |> assign(:composer_mode, :search)
             |> assign(:search_status, :idle)
             |> put_flash(:error, "유효한 링크를 입력해 주세요")}
        end
    end
  end

  @impl true
  def handle_event("start_create", _params, socket) do
    params = normalized_share_params(form_values(socket))

    if String.trim(params["tweet_url"]) == "" do
      {:noreply,
       socket
       |> assign(:share_form, share_form(params))
       |> assign(:composer_mode, :search)
       |> assign(:search_status, :idle)
       |> put_flash(:error, "링크를 입력해 주세요")}
    else
      {:noreply,
       socket
       |> assign(:share_form, share_form(params))
       |> assign(:composer_mode, :create)
       |> assign(:search_status, :idle)}
    end
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
  def handle_event("set_feed_sort", %{"sort" => sort}, socket) do
    next_sort = normalize_feed_sort(sort)
    {:noreply, assign_feed(socket, next_sort)}
  end

  @impl true
  def handle_info(:refresh_feed, socket) do
    socket =
      socket
      |> assign_feed(socket.assigns.feed_sort)
      |> maybe_schedule_feed_refresh()

    {:noreply, socket}
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
      <section id="landing-hero" class="x-compose-wrap">
        <.form
          for={@share_form}
          id="share-room-form"
          phx-submit={if @composer_mode == :create, do: "share_room", else: "search_link"}
          class="x-compose-form"
        >
          <div class="x-compose-primary-row">
            <.input
              id="share-link-url"
              field={@share_form[:tweet_url]}
              type="url"
              class="x-compose-input"
              placeholder="링크를 먼저 입력하세요"
            />

            <div class="x-compose-cta-row">
              <button
                :if={@composer_mode == :search}
                id="share-room-search"
                type="submit"
                class="mat-btn-secondary"
              >
                검색하기
              </button>

              <button
                :if={@composer_mode == :search and @search_status == :not_found}
                id="share-room-start-create"
                type="button"
                phx-click="start_create"
                class="mat-btn-primary"
              >
                새 방 만들기
              </button>

              <button
                :if={@composer_mode == :create}
                id="share-room-submit"
                type="submit"
                class="mat-btn-primary"
              >
                <.icon name="hero-plus" class="h-4 w-4" /> 방 만들기
              </button>
            </div>
          </div>

          <.input
            :if={@composer_mode == :create}
            id="share-title"
            field={@share_form[:title]}
            type="text"
            class="x-compose-link"
            placeholder="제목을 입력해 방 이름을 정하세요"
            required
          />
        </.form>

        <%= if !@authenticated do %>
          <div id="share-login-required" class="x-login-required">
            <p>비로그인 사용자는 조회만 가능합니다. 로그인하면 바로 방 생성이 가능합니다.</p>
            <.link id="share-login-link" navigate={~p"/login"} class="mat-btn-primary">
              Google 로그인 후 방 만들기
            </.link>
          </div>
        <% end %>
      </section>

      <section id="share-feed" class="x-feed-wrap">
        <div id="share-feed-controls" class="x-feed-controls">
          <form id="share-feed-sort-form" phx-change="set_feed_sort">
            <select id="share-feed-sort" name="sort" class="x-feed-select">
              <option value="latest" selected={@feed_sort == "latest"}>최신순</option>
              <option value="views" selected={@feed_sort == "views"}>조회순</option>
              <option value="live" selected={@feed_sort == "live"}>실시간 인기순</option>
            </select>
          </form>
        </div>

        <%= if @feed_posts == [] do %>
          <div id="share-feed-empty" class="x-feed-empty">아직 방이 없습니다. 첫 방을 만들어 보세요.</div>
        <% else %>
          <div id="share-feed-list" class="space-y-2.5">
            <%= for post <- @feed_posts do %>
              <.link
                id={"share-feed-item-#{post.id}"}
                navigate={~p"/rooms/#{post.id}"}
                class="mat-card block p-3"
              >
                <div class="flex items-center gap-2.5">
                  <p class="truncate text-sm font-bold text-slate-900">{display_title(post)}</p>
                  <span class="mat-pill px-2.5 py-1 text-[11px]">
                    현재 접속 {Map.get(@active_counts, post.id, 0)}
                  </span>
                </div>
                <p class="mt-1 truncate text-xs text-slate-500">{post.tweet_url}</p>
                <div class="mt-2 flex flex-wrap items-center gap-2 text-xs text-slate-700">
                  <span id={"share-feed-view-count-#{post.id}"}>조회수 {post.view_count}</span>
                  <span id={"share-feed-like-count-#{post.id}"}>좋아요 {post.like_count}</span>
                </div>
              </.link>
            <% end %>
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp empty_share_form do
    to_form(%{"title" => "", "tweet_url" => ""}, as: :share)
  end

  defp share_form(params) when is_map(params), do: to_form(params, as: :share)

  defp normalized_share_params(params) when is_map(params) do
    %{
      "title" => String.trim(params["title"] || ""),
      "tweet_url" => String.trim(params["tweet_url"] || "")
    }
  end

  defp form_values(socket) do
    %{
      "title" => socket.assigns.share_form[:title].value || "",
      "tweet_url" => socket.assigns.share_form[:tweet_url].value || ""
    }
  end

  defp maybe_schedule_feed_refresh(socket) do
    if connected?(socket) do
      Process.send_after(self(), :refresh_feed, @feed_refresh_ms)
    end

    socket
  end

  defp assign_feed(socket, sort) do
    posts =
      case sort do
        "views" -> Collab.list_posts(@feed_limit, sort: "views")
        "live" -> Collab.list_posts(@feed_limit, sort: "latest")
        _ -> Collab.list_posts(@feed_limit, sort: "latest")
      end

    active_counts = active_counts_map(posts)

    sorted_posts =
      case sort do
        "live" ->
          Enum.sort_by(
            posts,
            fn post ->
              {Map.get(active_counts, post.id, 0), post.inserted_at, post.id}
            end,
            :desc
          )

        _ ->
          posts
      end

    socket
    |> assign(:feed_sort, sort)
    |> assign(:feed_posts, sorted_posts)
    |> assign(:active_counts, active_counts)
    |> assign(:feed_loaded?, true)
  end

  defp active_counts_map(posts) do
    posts
    |> Enum.map(fn post ->
      count =
        post.id
        |> presence_topic()
        |> Presence.list()
        |> map_size()

      {post.id, count}
    end)
    |> Map.new()
  end

  defp presence_topic(post_id), do: "presence:#{post_id}"

  defp normalize_feed_sort(sort) when sort in ["latest", "views", "live"], do: sort
  defp normalize_feed_sort(_sort), do: "latest"

  defp display_title(post) do
    case String.trim(post.title || "") do
      "" -> "제목 없는 공유"
      title -> title
    end
  end

  defp logged_in?(session) when is_map(session) do
    case session["google_uid"] do
      uid when is_binary(uid) and uid != "" -> true
      _ -> false
    end
  end

  defp logged_in?(_session), do: false
end
