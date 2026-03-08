defmodule MatdoriWeb.MyPageLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab

  @profile_tabs ~w(created highlighted liked)
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
     |> assign(:profile_color, profile_color)
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
     |> assign(:profile_color, selected)
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
      topbar={%{mode: :profile, refresh_event: "refresh_profile_topbar"}}
    >
      <section id="my-page" class="my-page-shell">
        <div id="my-profile-header">
          <div class="my-profile-head">
            <div class="my-profile-avatar-wrap">
              <img
                :if={@avatar_url}
                id="my-profile-avatar"
                src={@avatar_url}
                alt="profile"
                class="my-profile-avatar"
              />
              <div
                :if={!@avatar_url}
                id="my-profile-avatar-fallback"
                class="my-profile-avatar-fallback"
              >
                <.icon name="hero-user" class="size-8" />
              </div>
            </div>
            <div class="my-profile-meta">
              <h1 id="my-profile-name" class="text-2xl font-black tracking-tight text-slate-900">
                {@display_name || "Profile"}
              </h1>
              <p :if={@email} id="my-profile-email" class="text-sm text-slate-500">{@email}</p>

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

        <div :if={@editing_profile} id="my-profile-edit-modal" class="my-profile-modal-backdrop">
          <div class="my-profile-modal-card" phx-click-away="close_profile_edit">
            <div class="my-profile-modal-head">
              <h2 class="text-lg font-black tracking-tight text-slate-900">Edit Profile</h2>
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
                <label for="my-profile-color-input" class="text-sm font-semibold text-slate-700">
                  My Color (cursor/comments/highlights)
                </label>
                <div class="flex items-center gap-3">
                  <.input
                    id="my-profile-color-input"
                    field={@profile_form[:color]}
                    type="color"
                    class="h-11 w-16 rounded-lg border border-slate-300 bg-white p-1"
                  />
                  <span class="text-sm font-semibold text-slate-600">{@profile_color}</span>
                  <span
                    id="my-profile-color-preview-code"
                    class="inline-block h-6 w-6 rounded-full border border-slate-300"
                    style={"background-color: #{@profile_color}"}
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
                        if(@profile_color == color,
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
          <h2 class="text-xl font-black tracking-tight text-slate-900">Rooms I Created</h2>
          <%= if @created_posts == [] do %>
            <p id="my-created-empty" class="my-profile-empty mt-3 text-sm text-slate-500">
              No rooms created yet.
            </p>
          <% else %>
            <div class="my-feed-list mt-4">
              <%= for post <- @created_posts do %>
                <article class="my-feed-card" id={"my-created-card-#{post.id}"}>
                  <div class="my-feed-head">
                    <div class="my-feed-author">
                      <span class="my-feed-avatar">{author_initial(@display_name)}</span>
                      <div class="my-feed-author-meta">
                        <p class="my-feed-author-line">
                          <span class="my-feed-name">{@display_name || "Profile"}</span>
                          <span class="my-feed-dot">·</span>
                          <span class="my-feed-date">{format_post_date(post.inserted_at)}</span>
                        </p>
                        <p class="my-feed-kind">Posted by me</p>
                      </div>
                    </div>

                    <.link
                      id={"my-created-room-#{post.id}"}
                      navigate={~p"/rooms/#{post.id}"}
                      class="my-feed-open-link"
                    >
                      View
                    </.link>

                    <button
                      id={"my-created-delete-#{post.id}"}
                      type="button"
                      phx-click="delete_created_post"
                      phx-value-post_id={post.id}
                      class="my-feed-delete-btn"
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                    </button>
                  </div>

                  <.link
                    id={"my-created-room-title-#{post.id}"}
                    navigate={~p"/rooms/#{post.id}"}
                    class="block"
                  >
                    <p class="my-feed-title">{display_title(post)}</p>
                    <p class="my-feed-body">{post.tweet_url}</p>
                  </.link>

                  <div class="my-feed-actions" aria-hidden="true">
                    <span class="my-feed-action">
                      <.icon name="hero-chat-bubble-left-right" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action">
                      <.icon name="hero-arrow-path-rounded-square" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action is-accent">
                      <.icon name="hero-heart" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action">
                      <.icon name="hero-chart-bar" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action"><.icon name="hero-bookmark" class="size-4" /></span>
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
          <h2 class="text-xl font-black tracking-tight text-slate-900">Rooms I Highlighted</h2>
          <%= if @highlighted_posts == [] do %>
            <p id="my-highlighted-empty" class="my-profile-empty mt-3 text-sm text-slate-500">
              No highlighted rooms.
            </p>
          <% else %>
            <div class="my-feed-list mt-4">
              <%= for post <- @highlighted_posts do %>
                <article class="my-feed-card" id={"my-highlighted-card-#{post.id}"}>
                  <div class="my-feed-head">
                    <div class="my-feed-author">
                      <span class="my-feed-avatar">{author_initial(@display_name)}</span>
                      <div class="my-feed-author-meta">
                        <p class="my-feed-author-line">
                          <span class="my-feed-name">{@display_name || "Profile"}</span>
                          <span class="my-feed-dot">·</span>
                          <span class="my-feed-date">{format_post_date(post.inserted_at)}</span>
                        </p>
                        <p class="my-feed-kind">Highlighted by me</p>
                      </div>
                    </div>

                    <.link
                      id={"my-highlighted-room-#{post.id}"}
                      navigate={~p"/rooms/#{post.id}"}
                      class="my-feed-open-link"
                    >
                      View
                    </.link>

                    <button
                      id={"my-highlighted-delete-#{post.id}"}
                      type="button"
                      phx-click="delete_my_highlights"
                      phx-value-post_id={post.id}
                      class="my-feed-delete-btn"
                    >
                      <.icon name="hero-trash" class="size-3.5" />
                    </button>
                  </div>

                  <.link
                    id={"my-highlighted-room-title-#{post.id}"}
                    navigate={~p"/rooms/#{post.id}"}
                    class="block"
                  >
                    <p class="my-feed-title">{display_title(post)}</p>
                    <p class="my-feed-body">{post.tweet_url}</p>
                  </.link>

                  <div class="my-feed-actions" aria-hidden="true">
                    <span class="my-feed-action">
                      <.icon name="hero-chat-bubble-left-right" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action">
                      <.icon name="hero-arrow-path-rounded-square" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action is-accent">
                      <.icon name="hero-heart" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action">
                      <.icon name="hero-chart-bar" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action"><.icon name="hero-bookmark" class="size-4" /></span>
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
          <h2 class="text-xl font-black tracking-tight text-slate-900">Rooms I Liked</h2>
          <%= if @liked_posts == [] do %>
            <p id="my-liked-empty" class="my-profile-empty mt-3 text-sm text-slate-500">
              No liked rooms.
            </p>
          <% else %>
            <div class="my-feed-list mt-4">
              <%= for post <- @liked_posts do %>
                <article class="my-feed-card" id={"my-liked-card-#{post.id}"}>
                  <div class="my-feed-head">
                    <div class="my-feed-author">
                      <span class="my-feed-avatar">{author_initial(@display_name)}</span>
                      <div class="my-feed-author-meta">
                        <p class="my-feed-author-line">
                          <span class="my-feed-name">{@display_name || "Profile"}</span>
                          <span class="my-feed-dot">·</span>
                          <span class="my-feed-date">{format_post_date(post.inserted_at)}</span>
                        </p>
                        <p class="my-feed-kind">Liked by me</p>
                      </div>
                    </div>

                    <.link
                      id={"my-liked-room-#{post.id}"}
                      navigate={~p"/rooms/#{post.id}"}
                      class="my-feed-open-link"
                    >
                      View
                    </.link>
                  </div>

                  <.link
                    id={"my-liked-room-title-#{post.id}"}
                    navigate={~p"/rooms/#{post.id}"}
                    class="block"
                  >
                    <p class="my-feed-title">{display_title(post)}</p>
                    <p class="my-feed-body">{post.tweet_url}</p>
                  </.link>

                  <div class="my-feed-actions" aria-hidden="true">
                    <span class="my-feed-action">
                      <.icon name="hero-chat-bubble-left-right" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action">
                      <.icon name="hero-arrow-path-rounded-square" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action is-accent">
                      <.icon name="hero-heart" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action">
                      <.icon name="hero-chart-bar" class="size-4" /> 0
                    </span>
                    <span class="my-feed-action"><.icon name="hero-bookmark" class="size-4" /></span>
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

  defp display_title(post) do
    case String.trim(post.title || "") do
      "" -> "Untitled Share"
      title -> title
    end
  end

  defp reload_profile_lists(socket) do
    socket
    |> assign(:created_posts, Collab.list_created_posts_by_google_uid(socket.assigns.google_uid))
    |> assign(:liked_posts, Collab.list_liked_posts_by_google_uid(socket.assigns.google_uid))
    |> assign(
      :highlighted_posts,
      Collab.list_highlighted_posts_for_user(socket.assigns.google_uid, socket.assigns.session_id)
    )
  end

  defp normalize_profile_tab(tab) when tab in @profile_tabs, do: tab
  defp normalize_profile_tab(_tab), do: "created"

  defp profile_tab_class(active?) do
    [
      "my-profile-tab",
      active? && "is-active"
    ]
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

  defp format_post_date(%DateTime{} = inserted_at) do
    date = DateTime.to_date(inserted_at)
    "#{date.month}/#{date.day}"
  end

  defp format_post_date(_inserted_at), do: "-"

  defp author_initial(name) when is_binary(name) do
    case String.trim(name) do
      "" -> "M"
      trimmed -> trimmed |> String.slice(0, 1) |> String.upcase()
    end
  end

  defp author_initial(_name), do: "M"
end
