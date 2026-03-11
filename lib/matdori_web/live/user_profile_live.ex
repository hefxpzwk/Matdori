defmodule MatdoriWeb.UserProfileLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.Embed
  alias MatdoriWeb.Presence

  @profile_tabs ~w(created active liked)
  @default_profile_color "#3b82f6"

  @impl true
  def mount(%{"google_uid" => google_uid}, session, socket) do
    profile_uid = normalize_google_uid(google_uid)
    profile = Collab.get_profile_by_google_uid(profile_uid)

    display_name = profile.display_name || "Profile"
    profile_color = normalize_profile_color(profile.color)

    created_posts = Collab.list_created_posts_by_google_uid(profile_uid, 30)
    active_posts = Collab.list_active_posts_by_google_uid(profile_uid, 30)
    liked_posts = Collab.list_liked_posts_by_google_uid(profile_uid, 30)
    active_counts = active_counts_map(created_posts ++ active_posts ++ liked_posts)

    {:ok,
     socket
     |> assign(:profile_uid, profile_uid)
     |> assign(:profile_name, display_name)
     |> assign(:profile_color, profile_color)
     |> assign(:profile_avatar_url, profile.avatar_url)
     |> assign(:profile_interests, profile.interests || [])
     |> assign(:viewer_display_name, session["display_name"])
     |> assign(:viewer_email, session["google_email"])
     |> assign(:viewer_avatar_url, session["google_avatar"])
     |> assign(:viewer_color, normalize_profile_color(session["color"]))
     |> assign(:viewer_authenticated, logged_in?(session))
     |> assign(:is_self, normalize_google_uid(session["google_uid"]) == profile_uid)
     |> assign(:active_tab, "created")
     |> assign(:created_posts, created_posts)
     |> assign(:active_posts, active_posts)
     |> assign(:liked_posts, liked_posts)
     |> assign(:active_counts, active_counts)}
  end

  @impl true
  def handle_event("switch_profile_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, normalize_profile_tab(tab))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={
        %{
          display_name: @viewer_display_name,
          color: @viewer_color,
          email: @viewer_email,
          avatar_url: @viewer_avatar_url,
          authenticated: @viewer_authenticated
        }
      }
      topbar={%{mode: :default}}
    >
      <section id="my-page" class="my-page-shell text-white">
        <div id="my-profile-header">
          <div class="my-profile-head">
            <div class="my-profile-avatar-wrap">
              <img
                :if={@profile_avatar_url}
                id="my-profile-avatar"
                src={@profile_avatar_url}
                alt={@profile_name}
                class="my-profile-avatar"
                style={"border-color: #{@profile_color}"}
              />
              <div
                :if={!@profile_avatar_url}
                id="my-profile-avatar-fallback"
                class="my-profile-avatar-fallback"
                style={"border-color: #{@profile_color}; color: #{@profile_color}"}
              >
                {profile_initial(@profile_name)}
              </div>
            </div>

            <div class="my-profile-meta">
              <h1 id="my-profile-name" class="text-2xl font-black tracking-tight text-white">
                {@profile_name}
              </h1>

              <div id="my-profile-interest" class="my-profile-interest">
                <%= for interest <- @profile_interests do %>
                  <span class="mat-pill my-interest-chip">{interest}</span>
                <% end %>
              </div>

              <div id="my-profile-color" class="my-profile-color-indicator">
                <span
                  id="my-profile-color-preview"
                  class="my-profile-color-dot"
                  style={"background-color: #{@profile_color}"}
                >
                </span>
                <span class="my-profile-color-code">{@profile_color}</span>
              </div>
            </div>

            <.link
              :if={@is_self}
              id="user-profile-my-page-link"
              navigate={~p"/me"}
              class="mat-btn-secondary my-profile-edit-btn"
            >
              Edit Profile
            </.link>
          </div>

          <div id="my-profile-tabs" class="my-profile-tabs">
            <button
              id="my-tab-created"
              type="button"
              phx-click="switch_profile_tab"
              phx-value-tab="created"
              class={profile_tab_class(@active_tab == "created")}
            >
              Created Rooms
            </button>
            <button
              id="my-tab-active"
              type="button"
              phx-click="switch_profile_tab"
              phx-value-tab="active"
              class={profile_tab_class(@active_tab == "active")}
            >
              Active Rooms
            </button>
            <button
              id="my-tab-liked"
              type="button"
              phx-click="switch_profile_tab"
              phx-value-tab="liked"
              class={profile_tab_class(@active_tab == "liked")}
            >
              Liked Rooms
            </button>
          </div>
        </div>

        <section
          :if={@active_tab == "created"}
          id="my-created-rooms"
          class="my-profile-content-panel px-0 py-6 sm:py-7"
        >
          <h2 class="text-xl font-black tracking-tight text-white">Created Rooms</h2>
          <%= if @created_posts == [] do %>
            <p id="my-created-empty" class="my-profile-empty mt-3 text-sm text-slate-300">
              No created rooms.
            </p>
          <% else %>
            <.profile_room_grid
              posts={@created_posts}
              id_prefix="my-created"
              active_counts={@active_counts}
            />
          <% end %>
        </section>

        <section
          :if={@active_tab == "active"}
          id="my-active-rooms"
          class="my-profile-content-panel px-0 py-6 sm:py-7"
        >
          <h2 class="text-xl font-black tracking-tight text-white">Active Rooms</h2>
          <%= if @active_posts == [] do %>
            <p id="my-active-empty" class="my-profile-empty mt-3 text-sm text-slate-300">
              No active rooms.
            </p>
          <% else %>
            <.profile_room_grid
              posts={@active_posts}
              id_prefix="my-active"
              active_counts={@active_counts}
            />
          <% end %>
        </section>

        <section
          :if={@active_tab == "liked"}
          id="my-liked-rooms"
          class="my-profile-content-panel px-0 py-6 sm:py-7"
        >
          <h2 class="text-xl font-black tracking-tight text-white">Liked Rooms</h2>
          <%= if @liked_posts == [] do %>
            <p id="my-liked-empty" class="my-profile-empty mt-3 text-sm text-slate-300">
              No liked rooms.
            </p>
          <% else %>
            <.profile_room_grid
              posts={@liked_posts}
              id_prefix="my-liked"
              active_counts={@active_counts}
            />
          <% end %>
        </section>
      </section>
    </Layouts.app>
    """
  end

  defp logged_in?(session), do: is_binary(session["google_uid"]) and session["google_uid"] != ""

  defp normalize_google_uid(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_google_uid(_value), do: nil

  defp normalize_profile_color(value) when is_binary(value) do
    trimmed = String.trim(value)

    if String.match?(trimmed, ~r/^#[0-9a-fA-F]{6}$/),
      do: String.downcase(trimmed),
      else: @default_profile_color
  end

  defp normalize_profile_color(_value), do: @default_profile_color

  defp profile_initial(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "P"
      first -> String.upcase(first)
    end
  end

  defp profile_initial(_name), do: "P"

  defp display_title(post) do
    case String.trim(post.title || "") do
      "" -> "Untitled Share"
      title -> title
    end
  end

  defp active_counts_map(posts) do
    posts
    |> Enum.map(fn post ->
      count = post.id |> presence_topic() |> Presence.list() |> map_size()
      {post.id, count}
    end)
    |> Map.new()
  end

  defp presence_topic(post_id), do: "presence:#{post_id}"

  defp preview_image_url(post) do
    case String.trim(post.preview_image_url || "") do
      "" -> nil
      url -> normalize_preview_image_url(url)
    end
  end

  defp og_preview_text(post) do
    preview = String.trim(post.preview_description || "")
    snapshot = snapshot_preview_text(post.current_snapshot)

    cond do
      preview != "" -> preview
      snapshot != nil -> snapshot
      String.trim(post.preview_title || "") != "" -> post.preview_title
      true -> "OG preview description is unavailable."
    end
  end

  defp snapshot_preview_text(%Ecto.Association.NotLoaded{}), do: nil
  defp snapshot_preview_text(nil), do: nil

  defp snapshot_preview_text(snapshot) do
    case String.trim(snapshot.normalized_text || "") do
      "" -> nil
      value -> value
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

  defp normalize_profile_tab(tab) when tab in @profile_tabs, do: tab
  defp normalize_profile_tab(_tab), do: "created"

  defp profile_tab_class(active?) do
    [
      "my-profile-tab",
      active? && "is-active"
    ]
  end

  attr :posts, :list, required: true
  attr :id_prefix, :string, required: true
  attr :active_counts, :map, required: true

  defp profile_room_grid(assigns) do
    ~H"""
    <div id={"#{@id_prefix}-room-media-grid"} class="x-media-grid mt-4" phx-hook="MasonryGrid">
      <%= for post <- @posts do %>
        <.link
          id={"#{@id_prefix}-room-#{post.id}"}
          navigate={~p"/rooms/#{post.id}"}
          class={media_card_class(post)}
        >
          <div class={media_frame_class(post)}>
            <%= cond do %>
              <% embed_provider(post) == :x -> %>
                <div
                  id={"#{@id_prefix}-x-embed-#{post.id}"}
                  class="x-media-x-embed"
                  phx-hook="XEmbed"
                  phx-update="ignore"
                  data-tweet-url={post.tweet_url}
                >
                </div>
              <% embed_provider(post) == :youtube and youtube_embed_url(post) -> %>
                <iframe
                  id={"#{@id_prefix}-youtube-#{post.id}"}
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
                  <p
                    id={"#{@id_prefix}-room-fallback-title-#{post.id}"}
                    class="x-media-fallback-title"
                  >
                    {display_title(post)}
                  </p>
                  <p class="x-media-fallback-url">{og_preview_text(post)}</p>
                </div>
            <% end %>

            <span id={"#{@id_prefix}-room-status-#{post.id}"} class="x-media-status">
              {embed_status_label(post)}
            </span>

            <div class="x-media-overlay">
              <p id={"#{@id_prefix}-room-title-#{post.id}"} class="x-media-title">
                {display_title(post)}
              </p>
              <div class="x-media-metrics">
                <span id={"#{@id_prefix}-like-count-#{post.id}"}>Likes {post.like_count}</span>
                <span id={"#{@id_prefix}-dislike-count-#{post.id}"}>
                  Dislikes {post.dislike_count}
                </span>
                <span id={"#{@id_prefix}-view-count-#{post.id}"}>Views {post.view_count}</span>
                <span id={"#{@id_prefix}-live-count-#{post.id}"}>
                  Active {Map.get(@active_counts, post.id, 0)}
                </span>
                <span id={"#{@id_prefix}-comment-count-#{post.id}"}>
                  Comments {post.comment_count}
                </span>
              </div>
            </div>
          </div>
        </.link>
      <% end %>
    </div>
    """
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
end
