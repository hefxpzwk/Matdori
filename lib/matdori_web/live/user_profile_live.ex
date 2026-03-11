defmodule MatdoriWeb.UserProfileLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias MatdoriWeb.Presence

  @profile_tabs ~w(created highlighted liked)
  @default_profile_color "#3b82f6"

  @impl true
  def mount(%{"google_uid" => google_uid}, session, socket) do
    profile_uid = normalize_google_uid(google_uid)
    profile = Collab.get_profile_by_google_uid(profile_uid)

    display_name = profile.display_name || "Profile"
    profile_color = normalize_profile_color(profile.color)

    created_posts = Collab.list_created_posts_by_google_uid(profile_uid, 30)
    highlighted_posts = Collab.list_highlighted_posts_by_google_uid(profile_uid, 30)
    liked_posts = Collab.list_liked_posts_by_google_uid(profile_uid, 30)
    active_counts = active_counts_map(created_posts ++ highlighted_posts ++ liked_posts)

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
     |> assign(:highlighted_posts, highlighted_posts)
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
              id="my-tab-highlighted"
              type="button"
              phx-click="switch_profile_tab"
              phx-value-tab="highlighted"
              class={profile_tab_class(@active_tab == "highlighted")}
            >
              Highlighted Rooms
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
            <div class="my-feed-list mt-4">
              <%= for post <- @created_posts do %>
                <article class="my-feed-card relative" id={"my-created-card-#{post.id}"}>
                  <.link
                    id={"my-created-room-#{post.id}"}
                    navigate={~p"/rooms/#{post.id}"}
                    class="absolute inset-0 z-10"
                    aria-label={"Open #{display_title(post)}"}
                  >
                  </.link>

                  <div class="my-feed-head">
                    <div class="my-feed-author">
                      <span class="my-feed-avatar">{profile_initial(@profile_name)}</span>
                      <div class="my-feed-author-meta">
                        <p class="my-feed-author-line">
                          <span class="my-feed-name">{@profile_name}</span>
                          <span class="my-feed-dot">·</span>
                          <span class="my-feed-date">{format_post_date(post.inserted_at)}</span>
                        </p>
                      </div>
                    </div>
                  </div>

                  <div class="my-feed-card-body relative z-[1]">
                    <p id={"my-created-room-title-#{post.id}"} class="my-feed-title">
                      {og_preview_title(post)}
                    </p>

                    <div class="mt-1.5 overflow-hidden rounded-lg border border-slate-200 bg-slate-950">
                      <%= if preview_image_url(post) do %>
                        <img
                          src={preview_image_url(post)}
                          alt={og_preview_title(post)}
                          class="x-media-thumb h-20 w-full object-cover"
                          loading="lazy"
                          referrerpolicy="no-referrer"
                        />
                      <% else %>
                        <div class="x-media-fallback h-20 p-2">
                          <p class="line-clamp-1 text-xs font-bold text-slate-900">
                            {og_preview_title(post)}
                          </p>
                          <p class="line-clamp-1 text-[11px] text-slate-600">
                            {og_preview_text(post)}
                          </p>
                          <p class="line-clamp-1 text-[10px] text-slate-500">
                            {og_preview_source(post)}
                          </p>
                        </div>
                      <% end %>
                    </div>

                    <p class="my-feed-body line-clamp-2">{og_preview_text(post)}</p>

                    <div class="my-feed-actions" aria-hidden="true">
                      <span id={"my-created-like-count-#{post.id}"} class="my-feed-action is-accent">
                        <.icon name="hero-hand-thumb-up" class="size-4" /> {post.like_count}
                      </span>
                      <span id={"my-created-dislike-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-hand-thumb-down" class="size-4" /> {post.dislike_count}
                      </span>
                      <span id={"my-created-view-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-chart-bar" class="size-4" /> {post.view_count}
                      </span>
                      <span id={"my-created-live-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-signal" class="size-4" /> {Map.get(
                          @active_counts,
                          post.id,
                          0
                        )}
                      </span>
                      <span id={"my-created-comment-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-chat-bubble-left-right" class="size-4" /> {post.comment_count}
                      </span>
                    </div>
                  </div>
                </article>
              <% end %>
            </div>
          <% end %>
        </section>

        <section
          :if={@active_tab == "highlighted"}
          id="my-highlighted-rooms"
          class="my-profile-content-panel px-0 py-6 sm:py-7"
        >
          <h2 class="text-xl font-black tracking-tight text-white">Highlighted Rooms</h2>
          <%= if @highlighted_posts == [] do %>
            <p id="my-highlighted-empty" class="my-profile-empty mt-3 text-sm text-slate-300">
              No highlighted rooms.
            </p>
          <% else %>
            <div class="my-feed-list mt-4">
              <%= for post <- @highlighted_posts do %>
                <article class="my-feed-card relative" id={"my-highlighted-card-#{post.id}"}>
                  <.link
                    id={"my-highlighted-room-#{post.id}"}
                    navigate={~p"/rooms/#{post.id}"}
                    class="absolute inset-0 z-10"
                    aria-label={"Open #{display_title(post)}"}
                  >
                  </.link>

                  <div class="my-feed-head">
                    <div class="my-feed-author">
                      <span class="my-feed-avatar">{profile_initial(@profile_name)}</span>
                      <div class="my-feed-author-meta">
                        <p class="my-feed-author-line">
                          <span class="my-feed-name">{@profile_name}</span>
                          <span class="my-feed-dot">·</span>
                          <span class="my-feed-date">{format_post_date(post.inserted_at)}</span>
                        </p>
                      </div>
                    </div>
                  </div>

                  <div class="my-feed-card-body relative z-[1]">
                    <p id={"my-highlighted-room-title-#{post.id}"} class="my-feed-title">
                      {og_preview_title(post)}
                    </p>

                    <div class="mt-1.5 overflow-hidden rounded-lg border border-slate-200 bg-slate-950">
                      <%= if preview_image_url(post) do %>
                        <img
                          src={preview_image_url(post)}
                          alt={og_preview_title(post)}
                          class="x-media-thumb h-20 w-full object-cover"
                          loading="lazy"
                          referrerpolicy="no-referrer"
                        />
                      <% else %>
                        <div class="x-media-fallback h-20 p-2">
                          <p class="line-clamp-1 text-xs font-bold text-slate-900">
                            {og_preview_title(post)}
                          </p>
                          <p class="line-clamp-1 text-[11px] text-slate-600">
                            {og_preview_text(post)}
                          </p>
                          <p class="line-clamp-1 text-[10px] text-slate-500">
                            {og_preview_source(post)}
                          </p>
                        </div>
                      <% end %>
                    </div>

                    <p class="my-feed-body line-clamp-2">{og_preview_text(post)}</p>

                    <div class="my-feed-actions" aria-hidden="true">
                      <span
                        id={"my-highlighted-like-count-#{post.id}"}
                        class="my-feed-action is-accent"
                      >
                        <.icon name="hero-hand-thumb-up" class="size-4" /> {post.like_count}
                      </span>
                      <span id={"my-highlighted-dislike-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-hand-thumb-down" class="size-4" /> {post.dislike_count}
                      </span>
                      <span id={"my-highlighted-view-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-chart-bar" class="size-4" /> {post.view_count}
                      </span>
                      <span id={"my-highlighted-live-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-signal" class="size-4" /> {Map.get(
                          @active_counts,
                          post.id,
                          0
                        )}
                      </span>
                      <span id={"my-highlighted-comment-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-chat-bubble-left-right" class="size-4" /> {post.comment_count}
                      </span>
                    </div>
                  </div>
                </article>
              <% end %>
            </div>
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
            <div class="my-feed-list mt-4">
              <%= for post <- @liked_posts do %>
                <article class="my-feed-card relative" id={"my-liked-card-#{post.id}"}>
                  <.link
                    id={"my-liked-room-#{post.id}"}
                    navigate={~p"/rooms/#{post.id}"}
                    class="absolute inset-0 z-10"
                    aria-label={"Open #{display_title(post)}"}
                  >
                  </.link>

                  <div class="my-feed-head">
                    <div class="my-feed-author">
                      <span class="my-feed-avatar">{profile_initial(@profile_name)}</span>
                      <div class="my-feed-author-meta">
                        <p class="my-feed-author-line">
                          <span class="my-feed-name">{@profile_name}</span>
                          <span class="my-feed-dot">·</span>
                          <span class="my-feed-date">{format_post_date(post.inserted_at)}</span>
                        </p>
                      </div>
                    </div>
                  </div>

                  <div class="my-feed-card-body relative z-[1]">
                    <p id={"my-liked-room-title-#{post.id}"} class="my-feed-title">
                      {og_preview_title(post)}
                    </p>

                    <div class="mt-1.5 overflow-hidden rounded-lg border border-slate-200 bg-slate-950">
                      <%= if preview_image_url(post) do %>
                        <img
                          src={preview_image_url(post)}
                          alt={og_preview_title(post)}
                          class="x-media-thumb h-20 w-full object-cover"
                          loading="lazy"
                          referrerpolicy="no-referrer"
                        />
                      <% else %>
                        <div class="x-media-fallback h-20 p-2">
                          <p class="line-clamp-1 text-xs font-bold text-slate-900">
                            {og_preview_title(post)}
                          </p>
                          <p class="line-clamp-1 text-[11px] text-slate-600">
                            {og_preview_text(post)}
                          </p>
                          <p class="line-clamp-1 text-[10px] text-slate-500">
                            {og_preview_source(post)}
                          </p>
                        </div>
                      <% end %>
                    </div>

                    <p class="my-feed-body line-clamp-2">{og_preview_text(post)}</p>

                    <div class="my-feed-actions" aria-hidden="true">
                      <span id={"my-liked-like-count-#{post.id}"} class="my-feed-action is-accent">
                        <.icon name="hero-hand-thumb-up" class="size-4" /> {post.like_count}
                      </span>
                      <span id={"my-liked-dislike-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-hand-thumb-down" class="size-4" /> {post.dislike_count}
                      </span>
                      <span id={"my-liked-view-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-chart-bar" class="size-4" /> {post.view_count}
                      </span>
                      <span id={"my-liked-live-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-signal" class="size-4" /> {Map.get(
                          @active_counts,
                          post.id,
                          0
                        )}
                      </span>
                      <span id={"my-liked-comment-count-#{post.id}"} class="my-feed-action">
                        <.icon name="hero-chat-bubble-left-right" class="size-4" /> {post.comment_count}
                      </span>
                    </div>
                  </div>
                </article>
              <% end %>
            </div>
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

  defp format_post_date(%DateTime{} = inserted_at) do
    date = DateTime.to_date(inserted_at)
    "#{date.month}/#{date.day}"
  end

  defp format_post_date(_inserted_at), do: "-"

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

  defp og_preview_title(post) do
    case String.trim(post.preview_title || "") do
      "" -> display_title(post)
      value -> value
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

  defp og_preview_source(post) do
    case URI.parse(String.trim(post.tweet_url || "")) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> "source unavailable"
    end
  end
end
