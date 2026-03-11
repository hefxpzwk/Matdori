defmodule MatdoriWeb.ShareLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.Embed
  alias Matdori.RateLimiter
  alias MatdoriWeb.Presence

  @action_limit 20
  @feed_limit 60
  @feed_refresh_ms 6_000
  @embed_filters ~w(all embedded preview)

  @impl true
  def mount(_params, session, socket) do
    authenticated = logged_in?(session)

    {:ok,
     socket
     |> assign(:session_id, session["session_id"])
     |> assign(:google_uid, session["google_uid"])
     |> assign(:display_name, session["display_name"])
     |> assign(:color, session["color"])
     |> assign(:email, session["google_email"])
     |> assign(:avatar_url, session["google_avatar"])
     |> assign(:authenticated, authenticated)
     |> assign(:composer_mode, :search)
     |> assign(:search_status, :idle)
     |> assign(:feed_sort, "latest")
     |> assign(:feed_embed_filter, "all")
     |> assign(:feed_posts, [])
     |> assign(:active_counts, %{})
     |> assign(:feed_loaded?, false)
     |> assign(:share_form, empty_share_form())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    sort = params |> Map.get("sort", socket.assigns.feed_sort) |> normalize_feed_sort()

    embed_filter =
      params
      |> Map.get("embed", socket.assigns.feed_embed_filter)
      |> normalize_feed_embed_filter()

    socket =
      socket
      |> assign_feed(sort, embed_filter)
      |> assign(:composer_mode, if(open_create_param?(params), do: :create, else: :search))
      |> assign(:search_status, :idle)
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
         |> put_flash(:error, "Please enter a link.")}

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
             |> put_flash(:info, "No existing room found. You can create a new one.")}

          {:error, :invalid_tweet_url} ->
            {:noreply,
             socket
             |> assign(:share_form, share_form(params))
             |> assign(:composer_mode, :search)
             |> assign(:search_status, :idle)
             |> put_flash(:error, "Please enter a valid link.")}
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
       |> put_flash(:error, "Please enter a link.")}
    else
      {:noreply,
       socket
       |> assign(:share_form, share_form(params))
       |> assign(:composer_mode, :create)
       |> assign(:search_status, :idle)}
    end
  end

  @impl true
  def handle_event("cancel_create", _params, socket) do
    {:noreply,
     socket
     |> assign(:composer_mode, :search)
     |> assign(:search_status, :not_found)}
  end

  @impl true
  def handle_event("share_room", %{"share" => share_params}, socket) do
    params = normalized_share_params(share_params)
    tweet_url = String.trim(params["tweet_url"])

    case Collab.find_post_by_url(tweet_url) do
      {:ok, post} ->
        {:noreply,
         socket
         |> assign(:composer_mode, :search)
         |> assign(:search_status, :found)
         |> put_flash(:info, "같은 주소의 방이 있습니다.")
         |> push_navigate(to: ~p"/rooms/#{post.id}")}

      :not_found ->
        with true <- socket.assigns.authenticated,
             :ok <- RateLimiter.allow?(socket.assigns.session_id, :share_room, @action_limit),
             {:ok, post} <-
               Collab.share_post(
                 Map.put(params, "google_uid", socket.assigns.google_uid),
                 socket.assigns.session_id
               ) do
          {:noreply,
           socket
           |> assign(:share_form, empty_share_form())
           |> assign(:composer_mode, :search)
           |> assign(:search_status, :idle)
           |> put_flash(:info, "A new room has been created.")
           |> push_navigate(to: ~p"/rooms/#{post.id}")}
        else
          false ->
            {:noreply,
             socket
             |> put_flash(:error, "Only signed-in users can create rooms.")
             |> push_navigate(to: ~p"/login")}

          {:error, :rate_limited} ->
            {:noreply, put_flash(socket, :error, "Too many requests. Please try again shortly.")}

          {:error, :invalid_title} ->
            {:noreply,
             socket
             |> assign(:share_form, share_form(params))
             |> assign(:composer_mode, :create)
             |> put_flash(:error, "Please enter a title.")}

          {:error, :invalid_tweet_url} ->
            {:noreply,
             socket
             |> assign(:share_form, share_form(params))
             |> assign(:composer_mode, :create)
             |> put_flash(:error, "Please enter a valid link.")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:share_form, share_form(params))
             |> assign(:composer_mode, :create)
             |> put_flash(:error, "Unable to create room.")}
        end

      {:error, :invalid_tweet_url} ->
        {:noreply,
         socket
         |> assign(:share_form, share_form(params))
         |> assign(:composer_mode, :create)
         |> put_flash(:error, "Please enter a valid link.")}
    end
  end

  @impl true
  def handle_event("set_feed_sort", %{"sort" => sort}, socket) do
    next_sort = normalize_feed_sort(sort)
    {:noreply, assign_feed(socket, next_sort, socket.assigns.feed_embed_filter)}
  end

  @impl true
  def handle_event("set_feed_embed", %{"embed" => embed_filter}, socket) do
    next_filter = normalize_feed_embed_filter(embed_filter)
    {:noreply, assign_feed(socket, socket.assigns.feed_sort, next_filter)}
  end

  @impl true
  def handle_info(:refresh_feed, socket) do
    socket =
      socket
      |> assign_feed(socket.assigns.feed_sort, socket.assigns.feed_embed_filter)
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
          color: @color,
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
          phx-submit="search_link"
          class="x-compose-form"
        >
          <%= if @composer_mode == :search do %>
            <div class="x-compose-primary-row">
              <.input
                id="share-link-url"
                field={@share_form[:tweet_url]}
                type="url"
                class="x-compose-input"
                placeholder="Enter a link first"
              />

              <div class="x-compose-cta-row">
                <button
                  :if={@search_status != :not_found}
                  id="share-room-search"
                  type="submit"
                  class="mat-btn-secondary"
                >
                  Search
                </button>

                <button
                  :if={@search_status == :not_found}
                  id="share-room-start-create"
                  type="button"
                  phx-click="start_create"
                  class="mat-btn-primary"
                >
                  Create New Room
                </button>
              </div>
            </div>
          <% end %>
        </.form>

        <%= if @composer_mode == :create do %>
          <div id="share-create-modal-backdrop" class="x-create-modal-backdrop">
            <div id="share-create-modal-card" class="x-create-modal-card">
              <div class="x-create-modal-head">
                <p class="x-create-modal-title">Create New Room</p>
                <button
                  id="share-create-cancel"
                  type="button"
                  phx-click="cancel_create"
                  class="x-create-modal-close"
                >
                  <.icon name="hero-x-mark" class="h-4 w-4" />
                </button>
              </div>

              <.form
                for={@share_form}
                id="share-create-form"
                phx-submit="share_room"
                class="x-create-modal-form"
              >
                <.input
                  id="share-create-link-url"
                  field={@share_form[:tweet_url]}
                  type="url"
                  class="x-compose-input"
                  placeholder="Enter a link"
                  required
                />
                <.input
                  id="share-title"
                  field={@share_form[:title]}
                  type="text"
                  class="x-compose-link"
                  placeholder="Enter a title for the room"
                  required
                />

                <div class="x-create-modal-actions">
                  <button type="button" phx-click="cancel_create" class="mat-btn-secondary">
                    Cancel
                  </button>
                  <button id="share-room-submit" type="submit" class="mat-btn-primary">
                    <.icon name="hero-plus" class="h-4 w-4" /> Create Room
                  </button>
                </div>
              </.form>
            </div>
          </div>
        <% end %>

        <%= if !@authenticated do %>
          <div id="share-login-required" class="x-login-required">
            <p>Guests can view only. Sign in to create rooms.</p>
            <.link id="share-login-link" navigate={~p"/login"} class="mat-btn-primary">
              Sign in with Google to create a room
            </.link>
          </div>
        <% end %>
      </section>

      <section id="share-feed" class="x-feed-wrap">
        <div id="share-feed-controls" class="x-feed-controls">
          <form id="share-feed-sort-form" phx-change="set_feed_sort">
            <select id="share-feed-sort" name="sort" class="x-feed-select">
              <option value="latest" selected={@feed_sort == "latest"}>Latest</option>
              <option value="views" selected={@feed_sort == "views"}>Most Viewed</option>
              <option value="live" selected={@feed_sort == "live"}>Live Popular</option>
            </select>
          </form>

          <div id="share-embed-filter-buttons" class="x-feed-embed-filters">
            <button
              id="share-embed-filter-all"
              type="button"
              phx-click="set_feed_embed"
              phx-value-embed="all"
              class={feed_embed_button_class(@feed_embed_filter == "all")}
            >
              All
            </button>
            <button
              id="share-embed-filter-embedded"
              type="button"
              phx-click="set_feed_embed"
              phx-value-embed="embedded"
              class={feed_embed_button_class(@feed_embed_filter == "embedded")}
            >
              Embeddable
            </button>
            <button
              id="share-embed-filter-preview"
              type="button"
              phx-click="set_feed_embed"
              phx-value-embed="preview"
              class={feed_embed_button_class(@feed_embed_filter == "preview")}
            >
              OG Preview Only
            </button>
          </div>
        </div>

        <%= if @feed_posts == [] do %>
          <div id="share-feed-empty" class="x-feed-empty">No rooms yet. Create the first room.</div>
        <% else %>
          <div id="share-feed-list" class="x-media-grid" phx-hook="MasonryGrid">
            <%= for post <- @feed_posts do %>
              <.link
                id={"share-feed-item-#{post.id}"}
                navigate={~p"/rooms/#{post.id}"}
                class={media_card_class(post)}
              >
                <div class={media_frame_class(post)}>
                  <%= cond do %>
                    <% embed_provider(post) == :x -> %>
                      <div
                        id={"share-feed-x-embed-#{post.id}"}
                        class="x-media-x-embed"
                        phx-hook="XEmbed"
                        phx-update="ignore"
                        data-tweet-url={post.tweet_url}
                      >
                      </div>
                    <% embed_provider(post) == :youtube and youtube_embed_url(post) -> %>
                      <iframe
                        id={"share-feed-youtube-#{post.id}"}
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
                        referrerpolicy="no-referrer"
                      />
                    <% true -> %>
                      <div class="x-media-fallback">
                        <p class="x-media-fallback-title">{display_title(post)}</p>
                        <p class="x-media-fallback-url">{og_preview_text(post)}</p>
                      </div>
                  <% end %>

                  <span class="x-media-status">
                    Active now {Map.get(@active_counts, post.id, 0)}
                  </span>

                  <div class="x-media-overlay">
                    <p class="x-media-title">{display_title(post)}</p>
                    <div class="x-media-metrics">
                      <span id={"share-feed-view-count-#{post.id}"}>Views {post.view_count}</span>
                      <span id={"share-feed-like-count-#{post.id}"}>Likes {post.like_count}</span>
                      <span id={"share-feed-dislike-count-#{post.id}"}>
                        Dislikes {post.dislike_count}
                      </span>
                      <span id={"share-feed-active-count-#{post.id}"}>
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

  defp assign_feed(socket, sort, embed_filter) do
    posts =
      case sort do
        "views" -> Collab.list_posts(@feed_limit, sort: "views")
        "live" -> Collab.list_posts(@feed_limit, sort: "latest")
        _ -> Collab.list_posts(@feed_limit, sort: "latest")
      end

    filtered_posts = filter_feed_by_embed(posts, embed_filter)

    active_counts = active_counts_map(filtered_posts)

    sorted_posts =
      case sort do
        "live" ->
          Enum.sort_by(
            filtered_posts,
            fn post ->
              {Map.get(active_counts, post.id, 0), post.inserted_at, post.id}
            end,
            :desc
          )

        _ ->
          filtered_posts
      end

    socket
    |> assign(:feed_sort, sort)
    |> assign(:feed_embed_filter, embed_filter)
    |> assign(:feed_posts, sorted_posts)
    |> assign(:active_counts, active_counts)
    |> assign(:feed_loaded?, true)
  end

  defp filter_feed_by_embed(posts, "all"), do: posts

  defp filter_feed_by_embed(posts, "embedded") do
    Enum.filter(posts, &(Embed.classify(&1.tweet_url).mode == :native_embed))
  end

  defp filter_feed_by_embed(posts, "preview") do
    Enum.filter(posts, &(Embed.classify(&1.tweet_url).mode == :preview_only))
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

  defp normalize_feed_embed_filter(filter) when filter in @embed_filters, do: filter
  defp normalize_feed_embed_filter(_filter), do: "all"

  defp open_create_param?(params) when is_map(params) do
    Map.get(params, "create") in ["1", "true", "yes"]
  end

  defp open_create_param?(_params), do: false

  defp feed_embed_button_class(active?) do
    [
      "mat-control-chip",
      if(active?, do: "is-active", else: nil)
    ]
  end

  defp display_title(post) do
    case String.trim(post.title || "") do
      "" -> "Untitled Share"
      title -> title
    end
  end

  defp preview_image_url(post) do
    case String.trim(post.preview_image_url || "") do
      "" -> nil
      url -> normalize_preview_image_url(url)
    end
  end

  defp normalize_preview_image_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} = parsed
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        parsed
        |> maybe_upgrade_to_https()
        |> URI.to_string()

      _ ->
        nil
    end
  end

  defp maybe_upgrade_to_https(%URI{scheme: "http"} = uri), do: %{uri | scheme: "https"}
  defp maybe_upgrade_to_https(uri), do: uri

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

  defp og_preview_text(post) do
    post.preview_description ||
      post.preview_title ||
      snapshot_preview_text(post.current_snapshot) ||
      "OG preview description is unavailable."
  end

  defp snapshot_preview_text(%Ecto.Association.NotLoaded{}), do: nil
  defp snapshot_preview_text(nil), do: nil
  defp snapshot_preview_text(snapshot), do: snapshot.normalized_text

  defp logged_in?(session) when is_map(session) do
    case session["google_uid"] do
      uid when is_binary(uid) and uid != "" -> true
      _ -> false
    end
  end

  defp logged_in?(_session), do: false
end
