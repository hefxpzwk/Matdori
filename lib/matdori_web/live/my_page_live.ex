defmodule MatdoriWeb.MyPageLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.Embed
  alias MatdoriWeb.Presence

  @profile_tabs ~w(created active liked)
  @default_profile_color "#3b82f6"
  @profile_preset_colors [
    "#ef4444",
    "#f97316",
    "#eab308",
    "#22c55e",
    "#06b6d4",
    "#3b82f6",
    "#8b5cf6",
    "#ec4899"
  ]

  @impl true
  def mount(_params, session, socket) do
    google_uid = session["google_uid"]
    session_id = session["session_id"]
    session_display_name = session["display_name"]
    email = session["google_email"]
    avatar_url = session["google_avatar"]

    profile = Collab.get_profile_by_google_uid(google_uid)
    display_name = profile.display_name || session_display_name || "Profile"

    profile_color =
      normalize_profile_color(profile.color || session["color"] || @default_profile_color)

    {:ok,
     socket
     |> assign(:google_uid, google_uid)
     |> assign(:session_id, session_id)
     |> assign(:session_display_name, session_display_name)
     |> assign(:display_name, display_name)
     |> assign(:profile_color, profile_color)
     |> assign(:email, email)
     |> assign(:avatar_url, avatar_url)
     |> assign(:active_tab, "created")
     |> assign(:profile_preset_colors, @profile_preset_colors)
     |> assign(:editing_profile, false)
     |> assign(:interests, profile.interests || [])
     |> assign(:profile_form, profile_form(display_name, profile.interests || [], profile_color))
     |> reload_profile_lists()}
  end

  @impl true
  def handle_event("switch_profile_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, normalize_profile_tab(tab))}
  end

  @impl true
  def handle_event("refresh_profile_topbar", _params, socket) do
    profile = Collab.get_profile_by_google_uid(socket.assigns.google_uid)

    display_name =
      profile.display_name || socket.assigns.session_display_name || socket.assigns.display_name ||
        "Profile"

    profile_color =
      normalize_profile_color(
        profile.color || socket.assigns.profile_color || @default_profile_color
      )

    {:noreply,
     socket
     |> reload_profile_lists()
     |> assign(:display_name, display_name)
     |> assign(:profile_color, profile_color)
     |> assign(:interests, profile.interests || [])
     |> assign(:profile_form, profile_form(display_name, profile.interests || [], profile_color))}
  end

  @impl true
  def handle_event("open_profile_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_profile, true)
     |> assign(
       :profile_form,
       profile_form(
         socket.assigns.display_name,
         socket.assigns.interests,
         socket.assigns.profile_color
       )
     )}
  end

  @impl true
  def handle_event("close_profile_edit", _params, socket) do
    {:noreply, assign(socket, :editing_profile, false)}
  end

  @impl true
  def handle_event("profile_form_change", %{"profile" => params}, socket) do
    display_name = String.trim(params["display_name"] || "")
    interests_input = params["interests_input"] || ""
    profile_color = normalize_profile_color(params["color"] || socket.assigns.profile_color)

    {:noreply,
     socket
     |> assign(
       :profile_form,
       profile_form_with_raw_interests(display_name, interests_input, profile_color)
     )}
  end

  @impl true
  def handle_event("pick_profile_color", %{"color" => color}, socket) do
    selected = normalize_profile_color(color)

    current_name =
      socket.assigns.profile_form[:display_name].value || socket.assigns.display_name || ""

    current_interests_input =
      socket.assigns.profile_form[:interests_input].value ||
        Enum.join(socket.assigns.interests || [], ", ")

    {:noreply,
     socket
     |> assign(
       :profile_form,
       profile_form_with_raw_interests(current_name, current_interests_input, selected)
     )}
  end

  @impl true
  def handle_event("save_profile", %{"profile" => params}, socket) do
    display_name = String.trim(params["display_name"] || "")
    interests = parse_interests(params["interests_input"] || "")
    profile_color = normalize_profile_color(params["color"] || socket.assigns.profile_color)

    cond do
      display_name == "" ->
        {:noreply,
         socket
         |> assign(:profile_form, profile_form(display_name, interests, profile_color))
         |> put_flash(:error, "Please enter a username.")}

      true ->
        case Collab.upsert_profile_by_google_uid(socket.assigns.google_uid, %{
               display_name: display_name,
               interests: interests,
               color: profile_color
             }) do
          {:ok, profile} ->
            saved_name = profile.display_name || display_name
            saved_interests = profile.interests || []
            saved_color = normalize_profile_color(profile.color || profile_color)

            {:noreply,
             socket
             |> assign(:display_name, saved_name)
             |> assign(:profile_color, saved_color)
             |> assign(:interests, saved_interests)
             |> assign(:editing_profile, false)
             |> assign(:profile_form, profile_form(saved_name, saved_interests, saved_color))
             |> put_flash(:info, "Profile saved.")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:profile_form, profile_form(display_name, interests, profile_color))
             |> put_flash(:error, "Could not save profile.")}
        end
    end
  end

  @impl true
  def handle_event("delete_created_post", %{"post_id" => post_id}, socket) do
    with {:ok, parsed_post_id} <- parse_post_id(post_id),
         {:ok, _post} <- Collab.delete_post_by_owner(parsed_post_id, socket.assigns.google_uid) do
      {:noreply,
       socket
       |> reload_profile_lists()
       |> put_flash(:info, "Your room was deleted.")}
    else
      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can delete only rooms you created.")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> reload_profile_lists()
         |> put_flash(:error, "Already deleted or room does not exist.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete room.")}
    end
  end

  @impl true
  def handle_event("delete_my_highlights", %{"post_id" => post_id}, socket) do
    with {:ok, parsed_post_id} <- parse_post_id(post_id),
         {:ok, result} <-
           Collab.delete_highlights_for_user_in_post(
             parsed_post_id,
             socket.assigns.google_uid,
             socket.assigns.session_id
           ) do
      message =
        if result.deleted_total > 0,
          do: "Your highlights were deleted.",
          else: "No highlights to delete."

      {:noreply,
       socket
       |> reload_profile_lists()
       |> put_flash(:info, message)}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Could not delete highlights.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={
        %{
          display_name: @display_name,
          color: @profile_color,
          email: @email,
          avatar_url: @avatar_url,
          authenticated: true
        }
      }
      topbar={%{mode: :default}}
    >
      <section id="my-page" class="my-page-shell text-white">
        <div id="my-profile-header">
          <div class="my-profile-head">
            <div class="my-profile-avatar-wrap">
              <img
                :if={@avatar_url}
                id="my-profile-avatar"
                src={@avatar_url}
                alt="profile"
                class="my-profile-avatar"
                style={"border-color: #{@profile_color}"}
              />
              <div
                :if={!@avatar_url}
                id="my-profile-avatar-fallback"
                class="my-profile-avatar-fallback"
                style={"border-color: #{@profile_color}; color: #{@profile_color}"}
              >
                <.icon name="hero-user" class="size-8" />
              </div>
            </div>
            <div class="my-profile-meta">
              <h1 id="my-profile-name" class="text-2xl font-black tracking-tight text-white">
                {@display_name || "Profile"}
              </h1>
              <p :if={@email} id="my-profile-email" class="text-sm text-slate-300">{@email}</p>

              <div id="my-profile-interest" class="my-profile-interest">
                <%= for interest <- @interests do %>
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

            <button
              id="my-profile-edit-toggle"
              type="button"
              class="mat-btn-secondary my-profile-edit-btn"
              phx-click="open_profile_edit"
            >
              Edit Profile
            </button>
          </div>

          <div id="my-profile-tabs" class="my-profile-tabs">
            <button
              id="my-tab-created"
              type="button"
              phx-click="switch_profile_tab"
              phx-value-tab="created"
              class={profile_tab_class(@active_tab == "created")}
            >
              My Rooms
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

        <div :if={@editing_profile} id="my-profile-edit-modal" class="my-profile-modal-backdrop">
          <div class="my-profile-modal-card" phx-click-away="close_profile_edit">
            <div class="my-profile-modal-head">
              <h2 class="text-lg font-black tracking-tight text-white">Edit Profile</h2>
              <button
                id="my-profile-edit-close"
                type="button"
                class="my-profile-modal-close"
                phx-click="close_profile_edit"
              >
                <.icon name="hero-x-mark" class="size-4" />
              </button>
            </div>

            <.form
              for={@profile_form}
              id="my-profile-edit-form"
              class="my-profile-edit-form"
              phx-change="profile_form_change"
              phx-submit="save_profile"
            >
              <.input
                id="my-profile-name-input"
                field={@profile_form[:display_name]}
                type="text"
                label="Username"
                required
              />
              <.input
                id="my-profile-interests-input"
                field={@profile_form[:interests_input]}
                type="text"
                label="Interests"
                placeholder="e.g. AI, startups, product design"
              />
              <div class="space-y-2">
                <label for="my-profile-color-input" class="text-sm font-semibold text-slate-100">
                  My Color (cursor/comments/highlights)
                </label>
                <div class="flex items-center gap-3">
                  <.input
                    id="my-profile-color-input"
                    field={@profile_form[:color]}
                    type="color"
                    class="h-11 w-16 rounded-lg border border-slate-300 bg-white p-1"
                  />
                  <span class="text-sm font-semibold text-slate-100">
                    {editing_profile_color(@profile_form, @profile_color)}
                  </span>
                  <span
                    id="my-profile-color-preview-code"
                    class="inline-block h-6 w-6 rounded-full border border-slate-300"
                    style={"background-color: #{editing_profile_color(@profile_form, @profile_color)}"}
                  >
                  </span>
                </div>

                <div id="my-profile-color-presets" class="flex flex-wrap gap-2">
                  <%= for color <- @profile_preset_colors do %>
                    <button
                      id={"my-profile-color-preset-#{String.trim_leading(color, "#")}"}
                      type="button"
                      phx-click="pick_profile_color"
                      phx-value-color={color}
                      class={[
                        "h-7 w-7 rounded-full border-2 transition",
                        if(editing_profile_color(@profile_form, @profile_color) == color,
                          do: "border-slate-900 scale-110",
                          else: "border-white hover:scale-105"
                        )
                      ]}
                      style={"background-color: #{color}"}
                    >
                    </button>
                  <% end %>
                </div>
              </div>
              <p class="my-profile-modal-help">Separate multiple items with commas (,).</p>

              <div class="my-profile-modal-actions">
                <button
                  id="my-profile-cancel"
                  type="button"
                  class="mat-btn-secondary"
                  phx-click="close_profile_edit"
                >
                  Cancel
                </button>
                <button id="my-profile-save" type="submit" class="mat-btn-primary">
                  Save
                </button>
              </div>
            </.form>
          </div>
        </div>

        <section
          :if={@active_tab == "created"}
          id="my-created-rooms"
          class="my-profile-content-panel px-0 py-6 sm:py-7"
        >
          <h2 class="text-xl font-black tracking-tight text-white">Rooms I Created</h2>
          <%= if @created_posts == [] do %>
            <p id="my-created-empty" class="my-profile-empty mt-3 text-sm text-slate-300">
              No rooms created yet.
            </p>
          <% else %>
            <.profile_room_grid
              posts={@created_posts}
              id_prefix="my-created"
              active_counts={@active_counts}
              delete_event="delete_created_post"
            />
          <% end %>
        </section>

        <section
          :if={@active_tab == "active"}
          id="my-active-rooms"
          class="my-profile-content-panel px-0 py-6 sm:py-7"
        >
          <h2 class="text-xl font-black tracking-tight text-white">Rooms I Was Active In</h2>
          <%= if @active_posts == [] do %>
            <p id="my-active-empty" class="my-profile-empty mt-3 text-sm text-slate-300">
              No active rooms.
            </p>
          <% else %>
            <.profile_room_grid
              posts={@active_posts}
              id_prefix="my-active"
              active_counts={@active_counts}
              delete_event="delete_my_highlights"
            />
          <% end %>
        </section>

        <section
          :if={@active_tab == "liked"}
          id="my-liked-rooms"
          class="my-profile-content-panel px-0 py-6 sm:py-7"
        >
          <h2 class="text-xl font-black tracking-tight text-white">Rooms I Liked</h2>
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

  defp display_title(post) do
    case String.trim(post.title || "") do
      "" -> "Untitled Share"
      title -> title
    end
  end

  defp reload_profile_lists(socket) do
    created_posts = Collab.list_created_posts_by_google_uid(socket.assigns.google_uid)
    liked_posts = Collab.list_liked_posts_by_google_uid(socket.assigns.google_uid)

    active_posts =
      Collab.list_active_posts_for_user(socket.assigns.google_uid, socket.assigns.session_id)

    active_counts = active_counts_map(created_posts ++ liked_posts ++ active_posts)

    socket
    |> assign(:created_posts, created_posts)
    |> assign(:liked_posts, liked_posts)
    |> assign(:active_posts, active_posts)
    |> assign(:active_counts, active_counts)
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
  attr :delete_event, :string, default: nil

  defp profile_room_grid(assigns) do
    ~H"""
    <div id={"#{@id_prefix}-room-media-grid"} class="x-media-grid mt-4" phx-hook="MasonryGrid">
      <%= for post <- @posts do %>
        <article class={[media_card_class(post), "relative"]}>
          <.link
            id={"#{@id_prefix}-room-#{post.id}"}
            navigate={~p"/rooms/#{post.id}"}
            class="absolute inset-0 z-10"
            aria-label={"Open #{display_title(post)}"}
          >
          </.link>

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

            <button
              :if={@delete_event}
              id={"#{@id_prefix}-delete-#{post.id}"}
              type="button"
              phx-click={@delete_event}
              phx-value-post_id={post.id}
              class="my-feed-delete-btn absolute right-2 top-2 z-20"
            >
              <.icon name="hero-trash" class="size-3.5" />
            </button>
          </div>
        </article>
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

  defp profile_form(display_name, interests, color) do
    to_form(
      %{
        "display_name" => display_name || "",
        "interests_input" => Enum.join(interests || [], ", "),
        "color" => normalize_profile_color(color)
      },
      as: :profile
    )
  end

  defp profile_form_with_raw_interests(display_name, interests_input, color) do
    to_form(
      %{
        "display_name" => display_name || "",
        "interests_input" => interests_input || "",
        "color" => normalize_profile_color(color)
      },
      as: :profile
    )
  end

  defp editing_profile_color(profile_form, fallback_color) do
    color = profile_form[:color].value || fallback_color
    normalize_profile_color(color)
  end

  defp parse_interests(input) when is_binary(input) do
    input
    |> String.split([",", "\n", "|"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.uniq()
    |> Enum.take(12)
  end

  defp parse_interests(_), do: []

  defp parse_post_id(post_id) when is_integer(post_id), do: {:ok, post_id}

  defp parse_post_id(post_id) when is_binary(post_id) do
    case Integer.parse(post_id) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_post_id}
    end
  end

  defp parse_post_id(_post_id), do: {:error, :invalid_post_id}

  defp normalize_profile_color(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(~r/^#[0-9a-fA-F]{6}$/, trimmed) do
      String.downcase(trimmed)
    else
      @default_profile_color
    end
  end

  defp normalize_profile_color(_value), do: @default_profile_color
end
