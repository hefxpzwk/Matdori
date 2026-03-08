defmodule MatdoriWeb.RoomIndexLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.Embed
  alias MatdoriWeb.Presence

  @embed_filters ~w(all embedded preview)
  @sort_options ~w(latest likes views)

  @impl true
  def mount(_params, session, socket) do
    authenticated = logged_in?(session)

    {:ok,
     socket
     |> assign(:posts, [])
     |> assign(:active_counts, %{})
     |> assign(:display_name, session["display_name"])
     |> assign(:color, session["color"])
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
     |> assign(:posts, posts)
     |> assign(:active_counts, active_counts_map(posts))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={
        %{
          display_name: @display_name,
          color: @color,
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
            <h1 class="mt-1 text-2xl font-black tracking-tight text-slate-900">Created Rooms</h1>
          </div>

          <%= if @authenticated do %>
            <.link
              id="go-share-page"
              navigate={~p"/"}
              class="mat-btn-primary"
            >
              Create New Room
            </.link>
          <% else %>
            <.link
              id="go-login-page"
              navigate={~p"/login"}
              class="mat-btn-secondary"
            >
              Log in
            </.link>
          <% end %>
        </div>

        <div
          id="room-list-controls"
          class="mat-panel grid gap-4 p-4 sm:grid-cols-2"
        >
          <div id="room-items" class="space-y-2">
            <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">Embed Filter</p>
            <div class="flex flex-wrap gap-2">
              <.link
                id="room-filter-all"
                patch={room_list_path("all", @sort)}
                class={control_link_class(@embed_filter == "all")}
              >
                All
              </.link>
              <.link
                id="room-filter-embedded"
                patch={room_list_path("embedded", @sort)}
                class={control_link_class(@embed_filter == "embedded")}
              >
                Embeddable
              </.link>
              <.link
                id="room-filter-preview"
                patch={room_list_path("preview", @sort)}
                class={control_link_class(@embed_filter == "preview")}
              >
                Preview Only
              </.link>
            </div>
          </div>

          <div class="space-y-2">
            <p class="text-xs font-semibold uppercase tracking-wide text-slate-500">Sort</p>
            <div class="flex flex-wrap gap-2">
              <.link
                id="room-sort-latest"
                patch={room_list_path(@embed_filter, "latest")}
                class={control_link_class(@sort == "latest")}
              >
                Latest
              </.link>
              <.link
                id="room-sort-likes"
                patch={room_list_path(@embed_filter, "likes")}
                class={control_link_class(@sort == "likes")}
              >
                Most Liked
              </.link>
              <.link
                id="room-sort-views"
                patch={room_list_path(@embed_filter, "views")}
                class={control_link_class(@sort == "views")}
              >
                Most Viewed
              </.link>
            </div>
          </div>
        </div>

        <%= if @posts == [] do %>
          <div
            id="room-list-empty"
            class="mat-panel p-5 text-sm text-slate-600"
          >
            No rooms yet. Create the first one from the home page.
          </div>
        <% else %>
          <div id="room-media-grid" class="x-media-grid" phx-hook="MasonryGrid">
            <%= for post <- @posts do %>
              <.link
                id={"room-item-#{post.id}"}
                navigate={~p"/rooms/#{post.id}"}
                class={media_card_class(post)}
              >
                <div class={media_frame_class(post)}>
                  <%= cond do %>
                    <% embed_provider(post) == :x -> %>
                      <div
                        id={"room-feed-x-embed-#{post.id}"}
                        class="x-media-x-embed"
                        phx-hook="XEmbed"
                        phx-update="ignore"
                        data-tweet-url={post.tweet_url}
                      >
                      </div>
                    <% embed_provider(post) == :youtube and youtube_embed_url(post) -> %>
                      <iframe
                        id={"room-feed-youtube-#{post.id}"}
                        src={youtube_embed_url(post)}
                        title={display_title(post)}
                        class="x-media-youtube"
                        loading="lazy"
                        referrerpolicy="strict-origin-when-cross-origin"
                        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                        allowfullscreen
                      >
                      </iframe>
                    <% preview_image_url(post) -> %>
                      <img
                        src={preview_image_url(post)}
                        alt={display_title(post)}
                        class="x-media-thumb"
                        loading="lazy"
                      />
                    <% true -> %>
                      <div class="x-media-fallback">
                        <p class="x-media-fallback-title">{display_title(post)}</p>
                        <p class="x-media-fallback-url">{fallback_preview_text(post)}</p>
                      </div>
                  <% end %>

                  <span
                    id={"room-status-#{post.id}"}
                    class="x-media-status"
                  >
                    {embed_status_label(post)}
                  </span>

                  <div class="x-media-overlay">
                    <p class="x-media-title">{display_title(post)}</p>
                    <div class="x-media-metrics">
                      <span id={"room-like-count-#{post.id}"}>Likes {post.like_count}</span>
                      <span id={"room-dislike-count-#{post.id}"}>Dislikes {post.dislike_count}</span>
                      <span id={"room-view-count-#{post.id}"}>Views {post.view_count}</span>
                      <span id={"room-active-count-#{post.id}"}>
                        Active {Map.get(@active_counts, post.id, 0)}
                      </span>
                    </div>
                  </div>
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
      "" -> "Untitled Share"
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
  defp embed_provider(post), do: post.tweet_url |> Embed.classify() |> Map.get(:provider)
  defp youtube_embed_url(post), do: post.tweet_url |> Embed.classify() |> Map.get(:embed_url)

  defp media_card_class(post) do
    [
      "x-media-card group",
      "x-media-card--#{media_type(post)}"
    ]
  end

  defp media_frame_class(post) do
    [
      "x-media-frame",
      "x-media-frame--#{media_type(post)}"
    ]
  end

  defp media_type(post) do
    cond do
      embed_provider(post) == :x -> "x"
      embed_provider(post) == :youtube and youtube_embed_url(post) -> "youtube"
      preview_image_url(post) -> "image"
      true -> "fallback"
    end
  end

  defp preview_image_url(post) do
    case String.trim(post.preview_image_url || "") do
      "" -> nil
      url -> url
    end
  end

  defp fallback_preview_text(post) do
    post.preview_description ||
      post.preview_title ||
      snapshot_preview_text(post.current_snapshot) ||
      post.tweet_url
  end

  defp snapshot_preview_text(%Ecto.Association.NotLoaded{}), do: nil
  defp snapshot_preview_text(nil), do: nil
  defp snapshot_preview_text(snapshot), do: snapshot.normalized_text

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

  defp logged_in?(session) when is_map(session) do
    case session["google_uid"] do
      uid when is_binary(uid) and uid != "" -> true
      _ -> false
    end
  end

  defp logged_in?(_session), do: false
end
