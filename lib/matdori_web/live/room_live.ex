defmodule MatdoriWeb.RoomLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.Embed
  alias Matdori.RateLimiter
  alias MatdoriWeb.Presence

  @cursor_limit 20
  @cursor_note_limit 30
  @cursor_note_max_len 80
  @overlay_draft_limit 30
  @action_limit 20

  @impl true
  def mount(_params, session, socket) do
    session_id = session["session_id"]
    display_name = session["display_name"]
    color = unique_cursor_color(session_id, session["color"])
    authenticated = logged_in?(session)

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:google_uid, session["google_uid"])
      |> assign(:display_name, display_name)
      |> assign(:email, session["google_email"])
      |> assign(:avatar_url, session["google_avatar"])
      |> assign(:color, color)
      |> assign(:authenticated, authenticated)
      |> assign(:post, nil)
      |> assign(:snapshot, nil)
      |> assign(:snapshot_versions, [])
      |> assign(:selected_version, nil)
      |> assign(:segments, [])
      |> assign(:highlights, [])
      |> assign(:room_comments, [])
      |> assign(:room_comment_form, empty_room_comment_form())
      |> assign(:overlay_highlights, [])
      |> assign(:overlay_highlight_comments, [])
      |> assign(:profile_overrides, %{})
      |> assign(:selected_highlight_id, nil)
      |> assign(:like_count, 0)
      |> assign(:dislike_count, 0)
      |> assign(:view_count, 0)
      |> assign(:liked, false)
      |> assign(:disliked, false)
      |> assign(:presence_members, %{})
      |> assign(:privacy_notice_open, true)
      |> assign(:room_identifier, nil)
      |> assign(:room_path, ~p"/rooms")

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case room_identifier_from_params(params) do
      {:post, _post_id} = room_identifier ->
        version = Map.get(params, "v")
        {:noreply, load_room(socket, room_identifier, version)}

      :invalid ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot find room.")
         |> push_navigate(to: ~p"/rooms")}
    end
  end

  @impl true
  def handle_event("change_version", %{"version" => version}, socket) do
    {:noreply, push_patch(socket, to: room_path_with_version(socket.assigns.room_path, version))}
  end

  def handle_event("cursor_move", %{"x" => x, "y" => y}, socket) do
    if socket.assigns.authenticated and
         RateLimiter.allow?(socket.assigns.session_id, :cursor_move, @cursor_limit, :second) ==
           :ok and
         socket.assigns.post do
      upsert_presence_meta(socket, fn meta ->
        next_meta = Map.put(meta, :cursor, normalize_cursor_position(x, y, meta_cursor(meta)))

        if meta_cursor_note_mode(meta) == "final" do
          next_meta
          |> Map.put(:cursor_note_text, "")
          |> Map.put(:cursor_note_mode, "clear")
          |> Map.put(:cursor_note_updated_at_ms, System.system_time(:millisecond))
        else
          next_meta
        end
      end)
    end

    {:noreply, socket}
  end

  def handle_event("cursor_note", %{"mode" => mode, "text" => text} = params, socket) do
    if socket.assigns.authenticated and
         RateLimiter.allow?(socket.assigns.session_id, :cursor_note, @cursor_note_limit, :second) ==
           :ok and
         socket.assigns.post do
      upsert_presence_meta(socket, fn meta ->
        cursor =
          normalize_cursor_position(Map.get(params, "x"), Map.get(params, "y"), meta_cursor(meta))

        normalized_text = normalize_cursor_note_text(text)
        normalized_mode = normalize_cursor_note_mode(mode, normalized_text)

        meta
        |> Map.put(:cursor, cursor)
        |> Map.put(:cursor_note_text, normalized_text)
        |> Map.put(:cursor_note_mode, normalized_mode)
        |> Map.put(:cursor_note_updated_at_ms, System.system_time(:millisecond))
      end)
    end

    {:noreply, socket}
  end

  def handle_event("overlay_highlights_sync", %{"highlights" => highlights}, socket) do
    if socket.assigns.authenticated and
         RateLimiter.allow?(
           socket.assigns.session_id,
           :overlay_highlights_sync,
           @action_limit,
           :second
         ) == :ok and socket.assigns.post do
      case Collab.replace_overlay_highlights(socket.assigns.post.id, %{
             session_id: socket.assigns.session_id,
             google_uid: socket.assigns.google_uid,
             display_name: socket.assigns.display_name,
             color: socket.assigns.color,
             highlights: highlights
           }) do
        {:ok, overlay_highlights} ->
          upsert_presence_meta(socket, fn meta ->
            Map.put(meta, :overlay_highlight_draft, nil)
          end)

          overlay_highlight_comments =
            Collab.list_overlay_highlight_comments(socket.assigns.post.id)

          profile_overrides =
            profile_overrides_for(
              socket.assigns.room_comments,
              socket.assigns.highlights,
              overlay_highlights,
              overlay_highlight_comments
            )

          broadcast_overlay_highlights(socket.assigns.post.id)

          {:noreply,
           socket
           |> assign(:overlay_highlights, overlay_highlights)
           |> assign(:overlay_highlight_comments, overlay_highlight_comments)
           |> assign(:profile_overrides, profile_overrides)
           |> push_overlay_highlight_states(overlay_highlights, overlay_highlight_comments)}

        {:error, _reason} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("overlay_highlight_draft", %{"zone" => zone}, socket) do
    if socket.assigns.authenticated and
         RateLimiter.allow?(
           socket.assigns.session_id,
           :overlay_highlight_draft,
           @overlay_draft_limit,
           :second
         ) == :ok and socket.assigns.post do
      upsert_presence_meta(socket, fn meta ->
        Map.put(meta, :overlay_highlight_draft, normalize_overlay_highlight_zone(zone))
      end)
    end

    {:noreply, socket}
  end

  def handle_event("overlay_highlight_draft", _params, socket), do: {:noreply, socket}

  def handle_event("overlay_highlight_comment_create", params, socket) do
    highlight_id = params["highlight_id"] || ""
    body = params["body"] || ""

    with true <- socket.assigns.authenticated,
         :ok <-
           RateLimiter.allow?(
             socket.assigns.session_id,
             :overlay_highlight_comment_create,
             @action_limit,
             :second
           ),
         %{id: post_id} <- socket.assigns.post,
         {:ok, _} <-
           Collab.create_overlay_highlight_comment(post_id, highlight_id, %{
             "session_id" => socket.assigns.session_id,
             "google_uid" => socket.assigns.google_uid,
             "display_name" => socket.assigns.display_name,
             "color" => socket.assigns.color,
             "body" => body
           }) do
      overlay_highlights = Collab.list_overlay_highlights(post_id)
      overlay_highlight_comments = Collab.list_overlay_highlight_comments(post_id)

      profile_overrides =
        profile_overrides_for(
          socket.assigns.room_comments,
          socket.assigns.highlights,
          overlay_highlights,
          overlay_highlight_comments
        )

      broadcast_overlay_highlights(post_id)

      {:noreply,
       socket
       |> assign(:overlay_highlights, overlay_highlights)
       |> assign(:overlay_highlight_comments, overlay_highlight_comments)
       |> assign(:profile_overrides, profile_overrides)
       |> push_overlay_highlight_states(overlay_highlights, overlay_highlight_comments)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("overlay_highlight_comment_delete", %{"comment_id" => id}, socket) do
    case Integer.parse(id || "") do
      {parsed_id, ""} ->
        with true <- socket.assigns.authenticated,
             :ok <-
               RateLimiter.allow?(
                 socket.assigns.session_id,
                 :overlay_highlight_comment_delete,
                 @action_limit,
                 :second
               ),
             %{id: post_id} <- socket.assigns.post,
             {:ok, _} <-
               Collab.soft_delete_overlay_highlight_comment(
                 post_id,
                 parsed_id,
                 socket.assigns.session_id,
                 socket.assigns.google_uid
               ) do
          overlay_highlights = Collab.list_overlay_highlights(post_id)
          overlay_highlight_comments = Collab.list_overlay_highlight_comments(post_id)

          profile_overrides =
            profile_overrides_for(
              socket.assigns.room_comments,
              socket.assigns.highlights,
              overlay_highlights,
              overlay_highlight_comments
            )

          broadcast_overlay_highlights(post_id)

          {:noreply,
           socket
           |> assign(:overlay_highlights, overlay_highlights)
           |> assign(:overlay_highlight_comments, overlay_highlight_comments)
           |> assign(:profile_overrides, profile_overrides)
           |> push_overlay_highlight_states(overlay_highlights, overlay_highlight_comments)}
        else
          _ -> {:noreply, socket}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_highlight", %{"highlight_id" => id}, socket) do
    case Integer.parse(id) do
      {parsed, ""} -> {:noreply, assign(socket, :selected_highlight_id, parsed)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("create_highlight", params, socket) do
    with true <- socket.assigns.authenticated,
         :ok <- RateLimiter.allow?(socket.assigns.session_id, :create_highlight, @action_limit),
         %{id: _} = snapshot <- socket.assigns.snapshot,
         {:ok, _highlight} <-
           Collab.create_highlight(
             snapshot,
             Map.merge(params, %{
               "session_id" => socket.assigns.session_id,
               "google_uid" => socket.assigns.google_uid,
               "display_name" => socket.assigns.display_name,
               "color" => socket.assigns.color
             })
           ) do
      broadcast_refresh(socket)
      {:noreply, reload_current_room(socket)}
    else
      false ->
        login_required_reply(socket)

      {:error, :overlap} ->
        {:noreply,
         put_flash(socket, :error, "The selected range overlaps an existing highlight.")}

      {:error, :ambiguous} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The selected range is ambiguous. Please select a more specific phrase."
         )}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, "Too many highlight requests. Please try again shortly.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to create highlight.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("comment_submit", %{"comment" => %{"body" => body}}, socket) do
    with true <- socket.assigns.authenticated,
         :ok <- RateLimiter.allow?(socket.assigns.session_id, :comment_submit, @action_limit),
         selected when is_integer(selected) <- socket.assigns.selected_highlight_id,
         {:ok, _comment} <-
           Collab.create_comment(selected, %{
             "session_id" => socket.assigns.session_id,
             "google_uid" => socket.assigns.google_uid,
             "display_name" => socket.assigns.display_name,
             "color" => socket.assigns.color,
             "body" => body
           }) do
      broadcast_refresh(socket)
      {:noreply, reload_current_room(socket)}
    else
      false ->
        login_required_reply(socket)

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "Too many comment requests. Please wait a moment.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to save comment.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Please select a highlight first.")}
    end
  end

  def handle_event("room_comment_submit", %{"room_comment" => %{"body" => body}}, socket) do
    with true <- socket.assigns.authenticated,
         :ok <- RateLimiter.allow?(socket.assigns.session_id, :comment_submit, @action_limit),
         %{id: post_id} <- socket.assigns.post,
         {:ok, _comment} <-
           Collab.create_room_comment(post_id, %{
             "session_id" => socket.assigns.session_id,
             "google_uid" => socket.assigns.google_uid,
             "display_name" => socket.assigns.display_name,
             "color" => socket.assigns.color,
             "body" => body
           }) do
      broadcast_refresh(socket)

      {:noreply,
       socket
       |> reload_current_room()
       |> assign(:room_comment_form, empty_room_comment_form())}
    else
      false ->
        login_required_reply(socket)

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "Too many comment requests. Please wait a moment.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to save room comment.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    with true <- socket.assigns.authenticated,
         :ok <- RateLimiter.allow?(socket.assigns.session_id, :delete_comment, @action_limit),
         {parsed, ""} <- Integer.parse(id),
         {:ok, _} <- Collab.soft_delete_comment(parsed, socket.assigns.session_id) do
      broadcast_refresh(socket)
      {:noreply, reload_current_room(socket)}
    else
      false ->
        login_required_reply(socket)

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "You can only delete your own recent comments.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Unable to delete comment.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"kind" => kind}, socket) do
    with true <- socket.assigns.authenticated,
         :ok <- RateLimiter.allow?(socket.assigns.session_id, :toggle_reaction, @action_limit),
         %{id: post_id} <- socket.assigns.post,
         {:ok, _} <-
           Collab.toggle_reaction(
             post_id,
             socket.assigns.session_id,
             kind,
             socket.assigns.google_uid
           ) do
      metrics = room_metrics(post_id)

      broadcast_room_metrics(post_id, metrics)

      {:noreply,
       socket
       |> assign(:like_count, metrics.like_count)
       |> assign(:dislike_count, metrics.dislike_count)
       |> assign(:view_count, metrics.view_count)
       |> assign(:liked, Collab.reacted_by?(post_id, socket.assigns.session_id, "like"))
       |> assign(:disliked, Collab.reacted_by?(post_id, socket.assigns.session_id, "dislike"))}
    else
      false ->
        login_required_reply(socket)

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "You are clicking too quickly.")}

      {:error, :invalid_reaction_kind} ->
        {:noreply, put_flash(socket, :error, "Unsupported reaction.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Unable to change reaction state.")}
    end
  end

  def handle_event("toggle_heart", _params, socket) do
    handle_event("toggle_reaction", %{"kind" => "like"}, socket)
  end

  def handle_event("submit_report", %{"report" => %{"reason" => reason}}, socket) do
    with true <- socket.assigns.authenticated,
         :ok <- RateLimiter.allow?(socket.assigns.session_id, :report, 5),
         %{id: post_id} <- socket.assigns.post,
         {:ok, _} <-
           Collab.create_report(post_id, %{
             "session_id" => socket.assigns.session_id,
             "google_uid" => socket.assigns.google_uid,
             "display_name" => socket.assigns.display_name,
             "reason" => reason
           }) do
      {:noreply, put_flash(socket, :info, "Report submitted. Thank you.")}
    else
      false ->
        login_required_reply(socket)

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "You have reached the current report limit.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Unable to submit report.")}
    end
  end

  def handle_event("update_name", %{"profile" => %{"display_name" => name}}, socket) do
    if socket.assigns.authenticated do
      cleaned =
        name
        |> String.trim()
        |> String.replace(~r/[^\p{L}\p{N}\s_-]/u, "")
        |> String.slice(0, 30)

      if cleaned == "" do
        {:noreply, put_flash(socket, :error, "Display name cannot be empty.")}
      else
        _ = Collab.update_display_name_by_google_uid(socket.assigns.google_uid || "", cleaned)

        if socket.assigns.post do
          upsert_presence_meta(
            assign(socket, :display_name, cleaned),
            &Map.put(&1, :display_name, cleaned)
          )
        end

        {:noreply,
         socket
         |> assign(:display_name, cleaned)
         |> put_flash(:info, "Display name was updated across your comments and highlights.")}
      end
    else
      login_required_reply(socket)
    end
  end

  def handle_event("dismiss_privacy", _params, socket) do
    {:noreply, assign(socket, :privacy_notice_open, false)}
  end

  @impl true
  def handle_event("refresh_room_topbar", _params, socket) do
    {:noreply, reload_current_room(socket)}
  end

  @impl true
  def handle_info({:room_refresh, _post_id}, socket) do
    {:noreply, reload_current_room(socket)}
  end

  def handle_info({:room_metrics, post_id, metrics}, socket) do
    if socket.assigns.post && socket.assigns.post.id == post_id do
      {:noreply,
       socket
       |> assign(:like_count, metrics.like_count)
       |> assign(:dislike_count, metrics.dislike_count)
       |> assign(:view_count, metrics.view_count)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:overlay_highlights_updated, post_id}, socket) do
    if socket.assigns.post && socket.assigns.post.id == post_id do
      overlay_highlights = Collab.list_overlay_highlights(post_id)
      overlay_highlight_comments = Collab.list_overlay_highlight_comments(post_id)

      profile_overrides =
        profile_overrides_for(
          socket.assigns.room_comments,
          socket.assigns.highlights,
          overlay_highlights,
          overlay_highlight_comments
        )

      {:noreply,
       socket
       |> assign(:overlay_highlights, overlay_highlights)
       |> assign(:overlay_highlight_comments, overlay_highlight_comments)
       |> assign(:profile_overrides, profile_overrides)
       |> push_overlay_highlight_states(overlay_highlights, overlay_highlight_comments)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    if socket.assigns.post do
      presences = Presence.list(presence_topic(socket.assigns.post.id))
      presence_members = presence_members_from_presences(presences)

      {:noreply,
       socket
       |> maybe_assign_presence_members(presence_members)
       |> push_event("presence_state", %{presences: presences, me: socket.assigns.session_id})}
    else
      {:noreply, socket}
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
          color: @color,
          email: @email,
          avatar_url: @avatar_url,
          authenticated: @authenticated
        }
      }
      topbar={%{mode: :default}}
    >
      <section class="-mt-2 space-y-5" id="room-detail">
        <%= if @post do %>
          <article
            id="room-collab-stage"
            phx-hook="SnapshotCanvas"
            data-cursor-color={@color}
            data-readonly={!@authenticated}
            class="mat-surface relative p-5 sm:p-6"
          >
            <div class="-ml-5 mb-1 flex flex-wrap items-center justify-between gap-3 sm:-ml-6">
              <div class="flex items-center gap-2">
                <h1 id="room-title" class="text-xl font-black tracking-tight text-slate-900">
                  {display_title(@post)}
                </h1>
                <span
                  id="room-embed-status"
                  class="mat-pill"
                >
                  {embed_status_label(@post)}
                </span>
              </div>
              <aside id="room-presence-panel" class="flex items-center gap-2">
                <p
                  id="room-presence-count"
                  aria-live="polite"
                  class="text-xs font-semibold text-slate-700"
                >
                  Live {participant_count(@presence_members)}
                </p>
                <div id="room-presence-list" class="flex -space-x-2">
                  <span
                    :for={{session_id, presence} <- @presence_members}
                    id={"room-presence-user-#{session_id}"}
                    title={presence_label(presence, session_id, @session_id)}
                    class="inline-flex h-7 w-7 items-center justify-center rounded-full border-2 border-white text-[11px] font-bold text-white shadow-sm"
                    style={"background-color: #{presence_color(presence)}"}
                  >
                    <img
                      :if={presence_avatar_url(presence)}
                      src={presence_avatar_url(presence)}
                      alt={presence_label(presence, session_id, @session_id)}
                      class="h-full w-full rounded-full object-cover"
                    />
                    <span :if={!presence_avatar_url(presence)}>
                      {presence_avatar_initial(presence, session_id, @session_id)}
                    </span>
                  </span>
                </div>
              </aside>
            </div>

            <div :if={!@post.hidden} id="room-source-link-row" class="mb-2 flex justify-end">
              <.link
                id="room-open-source-link"
                href={@post.tweet_url}
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center gap-1 rounded-full border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 transition hover:border-slate-400 hover:bg-slate-50"
              >
                <.icon name="hero-arrow-top-right-on-square" class="h-3.5 w-3.5" /> Open Original Link
              </.link>
            </div>

            <div id="room-content-layout" class="grid gap-4">
              <div id="room-main-column" class="order-2 min-w-0 space-y-4">
                <div :if={!@authenticated} id="room-login-required" class="text-sm text-slate-600">
                  Guests can view only.
                  <.link navigate={~p"/login"} class="font-semibold text-teal-700 underline">
                    Log in
                  </.link>
                  to use reactions/highlights/comments.
                </div>

                <%= if @post.hidden do %>
                  <div
                    id="takedown-state"
                    class="rounded-xl border border-rose-200 bg-rose-50 p-3 text-rose-800"
                  >
                    Content is unavailable.
                  </div>
                <% else %>
                  <div
                    id="room-embed-layout"
                    class="flex min-w-0 flex-col gap-3"
                  >
                    <div
                      id="room-embed-stage"
                      class="relative isolate overflow-hidden rounded-xl border border-slate-200 bg-slate-50/60 p-2"
                    >
                      <div id="room-embed-center-rail" class="flex w-full justify-center">
                        <div
                          id="room-embed-content"
                          class="relative w-[760px] min-w-[760px] max-w-[760px] shrink-0"
                        >
                          <%= if embed_provider(@post) == :x do %>
                            <div
                              id="tweet-embed"
                              phx-hook="XEmbed"
                              phx-update="ignore"
                              data-tweet-url={@post.tweet_url}
                              class="pointer-events-none min-h-24 rounded-xl border border-slate-200 bg-white p-2"
                            >
                              <blockquote class="twitter-tweet">
                                <a href={@post.tweet_url}>X Post</a>
                              </blockquote>
                            </div>
                          <% else %>
                            <%= if embed_provider(@post) == :youtube do %>
                              <div class="overflow-hidden rounded-xl border border-slate-200 bg-white">
                                <iframe
                                  id="youtube-embed"
                                  src={youtube_embed_url(@post)}
                                  class="pointer-events-none w-full"
                                  style="aspect-ratio: 16 / 9;"
                                  width="1280"
                                  height="720"
                                  title={display_title(@post)}
                                  allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                                  referrerpolicy="strict-origin-when-cross-origin"
                                  loading="lazy"
                                  allowfullscreen
                                >
                                </iframe>
                              </div>
                            <% else %>
                              <.preview_card post={@post} />
                            <% end %>
                          <% end %>

                          <div
                            id="embed-highlight-comment-panel"
                            class="pointer-events-auto absolute z-30 hidden w-[26rem] space-y-3 rounded-xl border border-slate-300 bg-white/97 p-4 shadow-xl backdrop-blur-sm"
                          >
                            <div
                              id="embed-highlight-comment-pointer"
                              class="absolute h-3 w-3 rotate-45 border border-slate-300 bg-white"
                            >
                            </div>

                            <div class="flex items-center justify-between gap-2">
                              <p
                                id="embed-highlight-comment-meta"
                                class="text-xs font-semibold text-slate-700"
                              >
                                Highlight
                              </p>
                              <button
                                id="embed-highlight-comment-close"
                                type="button"
                                class="inline-flex items-center gap-1 rounded-full border border-slate-300 bg-white px-2 py-1 text-xs font-semibold text-slate-700 transition hover:border-slate-400"
                              >
                                <.icon name="hero-x-mark" class="h-3.5 w-3.5" /> Close
                              </button>
                            </div>

                            <div
                              id="embed-highlight-comments-list"
                              class="max-h-52 space-y-2 overflow-y-auto pr-1"
                            >
                              <p class="text-sm text-slate-500">No comments yet.</p>
                            </div>

                            <div id="embed-highlight-comment-editor" class="hidden space-y-2">
                              <label
                                for="embed-highlight-comment-input"
                                class="text-xs font-medium text-slate-600"
                              >
                                Comment on this highlight
                              </label>
                              <div class="flex items-center gap-2">
                                <input
                                  id="embed-highlight-comment-input"
                                  type="text"
                                  maxlength="240"
                                  class="h-9 w-full rounded-lg border border-slate-300 bg-white px-3 text-sm text-slate-800 outline-none transition focus:border-teal-400"
                                  placeholder="Share what this highlight means"
                                />
                                <button
                                  id="embed-highlight-comment-save"
                                  type="button"
                                  class="inline-flex h-9 shrink-0 items-center gap-1 rounded-full border border-teal-300 bg-teal-50 px-3 text-xs font-semibold text-teal-700 transition hover:bg-teal-100"
                                >
                                  <.icon name="hero-paper-airplane" class="h-3.5 w-3.5" /> Send
                                </button>
                              </div>
                              <div class="flex justify-end">
                                <button
                                  id="embed-highlight-delete"
                                  type="button"
                                  class="inline-flex items-center gap-1 rounded-full border border-rose-300 bg-rose-50 px-3 py-1.5 text-xs font-semibold text-rose-700 transition hover:bg-rose-100"
                                >
                                  <.icon name="hero-trash" class="h-3.5 w-3.5" /> Delete Highlight
                                </button>
                              </div>
                            </div>
                          </div>

                          <div
                            id="room-embed-highlight-overlay"
                            phx-hook="EmbedHighlightOverlay"
                            phx-update="ignore"
                            data-readonly={!@authenticated}
                            data-stage-selector="#room-embed-content"
                            data-toggle-selector="#embed-highlight-mode-toggle"
                            data-count-selector="#embed-highlight-count"
                            data-comment-panel-selector="#embed-highlight-comment-panel"
                            data-comment-meta-selector="#embed-highlight-comment-meta"
                            data-comment-list-selector="#embed-highlight-comments-list"
                            data-comment-editor-selector="#embed-highlight-comment-editor"
                            data-comment-input-selector="#embed-highlight-comment-input"
                            data-comment-save-selector="#embed-highlight-comment-save"
                            data-highlight-delete-selector="#embed-highlight-delete"
                            data-comment-close-selector="#embed-highlight-comment-close"
                            data-comment-pointer-selector="#embed-highlight-comment-pointer"
                            data-session-id={@session_id}
                            data-user-color={@color}
                            class="pointer-events-none absolute inset-0 z-10 overflow-hidden rounded-lg"
                          >
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>

                  <p :if={embed_provider(@post) == :x} class="mt-2 text-xs text-slate-500">
                    If the embed does not load, use the original link above.
                  </p>
                <% end %>
              </div>

              <aside
                id="room-side-column"
                class="order-1 space-y-3"
              >
                <div
                  id="room-reactions"
                  class="flex flex-nowrap items-center gap-1.5"
                >
                  <button
                    id="like-button"
                    type="button"
                    phx-click="toggle_reaction"
                    phx-value-kind="like"
                    disabled={!@authenticated}
                    class={[
                      "inline-flex shrink-0 items-center gap-1 rounded-full border px-2.5 py-1 text-xs font-semibold transition",
                      if(@liked,
                        do: "border-emerald-400 bg-emerald-50 text-emerald-700",
                        else: "border-slate-300 bg-white text-slate-700 hover:border-slate-400"
                      ),
                      !@authenticated && "cursor-not-allowed opacity-50"
                    ]}
                  >
                    <.icon name="hero-hand-thumb-up" class="h-4 w-4" /> Like
                    <span id="like-count">{@like_count}</span>
                  </button>

                  <button
                    id="dislike-button"
                    type="button"
                    phx-click="toggle_reaction"
                    phx-value-kind="dislike"
                    disabled={!@authenticated}
                    class={[
                      "inline-flex shrink-0 items-center gap-1 rounded-full border px-2.5 py-1 text-xs font-semibold transition",
                      if(@disliked,
                        do: "border-rose-400 bg-rose-50 text-rose-700",
                        else: "border-slate-300 bg-white text-slate-700 hover:border-slate-400"
                      ),
                      !@authenticated && "cursor-not-allowed opacity-50"
                    ]}
                  >
                    <.icon name="hero-hand-thumb-down" class="h-4 w-4" /> Dislike
                    <span id="dislike-count">{@dislike_count}</span>
                  </button>

                  <span
                    id="room-view-count"
                    class="inline-flex shrink-0 items-center gap-1 rounded-full border border-slate-300 bg-white px-2.5 py-1 text-xs font-semibold text-slate-700"
                  >
                    Views {@view_count}
                  </span>

                  <div
                    :if={!@post.hidden}
                    id="embed-highlight-controls"
                    class="inline-flex shrink-0 items-center gap-1.5"
                  >
                    <button
                      id="embed-highlight-mode-toggle"
                      type="button"
                      data-highlight-overlay-toggle
                      disabled={!@authenticated}
                      aria-pressed="false"
                      class="inline-flex shrink-0 items-center gap-1 rounded-full border border-slate-300 bg-white px-2.5 py-1 text-xs font-semibold text-slate-700 transition hover:border-slate-400"
                    >
                      <.icon name="hero-pencil-square" class="h-3.5 w-3.5" /> Highlight
                      <span id="embed-highlight-mode-state">OFF</span>
                    </button>
                    <span
                      id="embed-highlight-count"
                      class="inline-flex shrink-0 items-center rounded-full border border-amber-300 bg-amber-50 px-2.5 py-1 text-xs font-semibold text-amber-700"
                    >
                      0 selected
                    </span>
                  </div>
                </div>
              </aside>
            </div>

            <div
              id="room-remote-cursors"
              phx-hook="RemoteCursors"
              phx-update="ignore"
              class="pointer-events-none absolute inset-0 z-20 overflow-hidden rounded-2xl"
            >
            </div>
          </article>

          <div id="room-comments-section" class="mat-surface space-y-4 p-5 sm:p-6">
            <div class="flex items-center gap-2">
              <.icon name="hero-chat-bubble-left-right" class="h-5 w-5 text-teal-600" />
              <h2 id="room-comments-title" class="text-base font-black tracking-tight text-slate-900">
                Room Comments
              </h2>
            </div>

            <%= if @authenticated do %>
              <.form for={@room_comment_form} id="room-comment-form" phx-submit="room_comment_submit">
                <.input
                  field={@room_comment_form[:body]}
                  type="textarea"
                  id="room-comment-body"
                  phx-hook="RoomCommentEnterSubmit"
                  placeholder="Leave a comment about the whole room"
                  rows="3"
                />
                <div class="mt-2 flex justify-end">
                  <button
                    id="room-comment-submit"
                    type="submit"
                    class="inline-flex items-center gap-1 rounded-full border border-teal-300 bg-teal-50 px-3 py-1.5 text-xs font-semibold text-teal-700 transition hover:bg-teal-100"
                  >
                    <.icon name="hero-paper-airplane" class="h-3.5 w-3.5" /> Post Comment
                  </button>
                </div>
              </.form>
            <% else %>
              <p id="room-comment-login-note" class="text-sm text-slate-600">
                Log in to leave a room-level comment.
              </p>
            <% end %>

            <div id="room-comments-list" class="space-y-3">
              <div :if={@room_comments == []} id="room-comments-empty" class="text-sm text-slate-500">
                No room comments yet.
              </div>

              <div
                :for={comment <- @room_comments}
                id={"room-comment-#{comment.id}"}
                class="relative"
              >
                <button
                  :if={
                    @authenticated and comment.session_id == @session_id and
                      comment.body != "[deleted]"
                  }
                  id={"room-comment-delete-#{comment.id}"}
                  type="button"
                  phx-click="delete_comment"
                  phx-value-id={comment.id}
                  class="absolute right-0 top-0 inline-flex items-center gap-1 rounded-full border border-slate-300 bg-white px-2 py-1 text-xs font-semibold text-slate-600 transition hover:border-slate-400"
                >
                  <.icon name="hero-trash" class="h-3.5 w-3.5" /> Delete
                </button>

                <div class="relative pr-20 text-left">
                  <div class="flex items-center gap-2">
                    <.link
                      :if={user_profile_path_from(comment)}
                      id={"room-comment-profile-#{comment.id}"}
                      navigate={user_profile_path_from(comment)}
                      class="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-slate-200 bg-slate-100 text-xs font-bold text-slate-700 transition hover:scale-105"
                      style={
                        "border-color: #{resolved_comment_color(comment, @profile_overrides)}; color: #{resolved_comment_color(comment, @profile_overrides)};"
                      }
                    >
                      <img
                        :if={
                          comment_avatar_url(
                            comment,
                            @presence_members,
                            @session_id,
                            @avatar_url,
                            @profile_overrides
                          )
                        }
                        src={
                          comment_avatar_url(
                            comment,
                            @presence_members,
                            @session_id,
                            @avatar_url,
                            @profile_overrides
                          )
                        }
                        alt={resolved_comment_display_name(comment, @profile_overrides)}
                        class="h-full w-full rounded-full object-cover"
                      />
                      <span :if={
                        !comment_avatar_url(
                          comment,
                          @presence_members,
                          @session_id,
                          @avatar_url,
                          @profile_overrides
                        )
                      }>
                        {comment_profile_initial(
                          resolved_comment_display_name(comment, @profile_overrides)
                        )}
                      </span>
                    </.link>

                    <span
                      :if={!user_profile_path_from(comment)}
                      id={"room-comment-profile-#{comment.id}"}
                      class="inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-slate-200 bg-slate-100 text-xs font-bold text-slate-700"
                      style={
                        "border-color: #{resolved_comment_color(comment, @profile_overrides)}; color: #{resolved_comment_color(comment, @profile_overrides)};"
                      }
                    >
                      <img
                        :if={
                          comment_avatar_url(
                            comment,
                            @presence_members,
                            @session_id,
                            @avatar_url,
                            @profile_overrides
                          )
                        }
                        src={
                          comment_avatar_url(
                            comment,
                            @presence_members,
                            @session_id,
                            @avatar_url,
                            @profile_overrides
                          )
                        }
                        alt={resolved_comment_display_name(comment, @profile_overrides)}
                        class="h-full w-full rounded-full object-cover"
                      />
                      <span :if={
                        !comment_avatar_url(
                          comment,
                          @presence_members,
                          @session_id,
                          @avatar_url,
                          @profile_overrides
                        )
                      }>
                        {comment_profile_initial(
                          resolved_comment_display_name(comment, @profile_overrides)
                        )}
                      </span>
                    </span>

                    <.link
                      :if={user_profile_path_from(comment)}
                      id={"room-comment-author-#{comment.id}"}
                      navigate={user_profile_path_from(comment)}
                      class="text-xs font-semibold text-slate-700 underline-offset-2 transition hover:text-teal-700 hover:underline"
                    >
                      {resolved_comment_display_name(comment, @profile_overrides)}
                    </.link>

                    <p
                      :if={!user_profile_path_from(comment)}
                      id={"room-comment-author-#{comment.id}"}
                      class="text-xs font-semibold text-slate-700"
                    >
                      {resolved_comment_display_name(comment, @profile_overrides)}
                    </p>

                    <time
                      id={"room-comment-time-#{comment.id}"}
                      datetime={DateTime.to_iso8601(comment.inserted_at)}
                      class="text-[11px] text-slate-500"
                    >
                      {format_comment_time(comment.inserted_at)}
                    </time>
                  </div>

                  <div class="mt-1 grid grid-cols-[2.25rem_minmax(0,1fr)] items-start gap-x-1">
                    <span class="inline-flex h-6 items-start justify-end pr-1 pt-0.5 text-sm font-semibold leading-none text-slate-400 select-none">
                      ㄴ
                    </span>

                    <p class="break-words pt-0.5 text-sm leading-relaxed text-slate-800">
                      {comment.body}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% else %>
          <div
            id="empty-state"
            class="mat-surface p-6 text-slate-700"
          >
            Room not found. Please choose again from the room list.
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp load_room(socket, room_identifier, selected_version) do
    case fetch_post(room_identifier) do
      nil ->
        socket
        |> maybe_unsubscribe_from_previous_topics(nil)
        |> assign(:room_identifier, room_identifier)
        |> assign(:room_path, room_path(room_identifier))
        |> assign(:post, nil)
        |> assign(:snapshot, nil)
        |> assign(:snapshot_versions, [])
        |> assign(:selected_version, nil)
        |> assign(:segments, [])
        |> assign(:highlights, [])
        |> assign(:room_comments, [])
        |> assign(:room_comment_form, empty_room_comment_form())
        |> assign(:overlay_highlights, [])
        |> assign(:overlay_highlight_comments, [])
        |> assign(:profile_overrides, %{})
        |> assign(:like_count, 0)
        |> assign(:dislike_count, 0)
        |> assign(:view_count, 0)
        |> assign(:liked, false)
        |> assign(:disliked, false)
        |> assign(:presence_members, %{})

      post ->
        view_status = Collab.register_view_with_status(post.id, socket.assigns.session_id)

        metrics = room_metrics(post.id)

        if view_status == :inserted do
          broadcast_room_metrics(post.id, metrics)
        end

        version = selected_version || (post.current_snapshot && post.current_snapshot.version)
        active_snapshot = resolve_snapshot(post, version)
        highlights = if active_snapshot, do: Collab.list_highlights(active_snapshot.id), else: []
        room_comments = Collab.list_room_comments(post.id)
        overlay_highlights = Collab.list_overlay_highlights(post.id)
        overlay_highlight_comments = Collab.list_overlay_highlight_comments(post.id)

        profile_overrides =
          profile_overrides_for(
            room_comments,
            highlights,
            overlay_highlights,
            overlay_highlight_comments
          )

        socket =
          socket
          |> maybe_unsubscribe_from_previous_topics(post)
          |> maybe_subscribe_to_topics(post)

        presences = Presence.list(presence_topic(post.id))

        socket
        |> assign(:room_identifier, room_identifier)
        |> assign(:room_path, room_path(room_identifier))
        |> assign(:post, post)
        |> assign(:snapshot, active_snapshot)
        |> assign(:snapshot_versions, Enum.map(post.snapshots, & &1.version))
        |> assign(:selected_version, active_snapshot && active_snapshot.version)
        |> assign(:highlights, highlights)
        |> assign(:room_comments, room_comments)
        |> assign(:room_comment_form, empty_room_comment_form())
        |> assign(:overlay_highlights, overlay_highlights)
        |> assign(:overlay_highlight_comments, overlay_highlight_comments)
        |> assign(:profile_overrides, profile_overrides)
        |> assign(
          :segments,
          build_segments((active_snapshot && active_snapshot.normalized_text) || "", highlights)
        )
        |> assign(:like_count, metrics.like_count)
        |> assign(:dislike_count, metrics.dislike_count)
        |> assign(:view_count, metrics.view_count)
        |> assign(:liked, Collab.reacted_by?(post.id, socket.assigns.session_id, "like"))
        |> assign(:disliked, Collab.reacted_by?(post.id, socket.assigns.session_id, "dislike"))
        |> assign(:presence_members, presence_members_from_presences(presences))
        |> push_overlay_highlight_states(overlay_highlights, overlay_highlight_comments)
        |> push_event("presence_state", %{presences: presences, me: socket.assigns.session_id})
    end
  end

  defp reload_current_room(socket) do
    load_room(socket, socket.assigns.room_identifier, socket.assigns.selected_version)
  end

  defp room_identifier_from_params(%{"post_id" => post_id}) do
    case Integer.parse(post_id) do
      {parsed, ""} -> {:post, parsed}
      _ -> :invalid
    end
  end

  defp room_identifier_from_params(_params), do: :invalid

  defp fetch_post({:post, post_id}), do: Collab.get_post_with_versions(post_id)

  defp room_path({:post, post_id}), do: ~p"/rooms/#{post_id}"

  defp room_path_with_version(path, version), do: path <> "?v=#{version}"

  defp empty_room_comment_form do
    to_form(%{"body" => ""}, as: :room_comment)
  end

  defp maybe_subscribe_to_topics(socket, post) do
    previous_post_id = socket.assigns.post && socket.assigns.post.id

    if connected?(socket) and previous_post_id != post.id do
      Phoenix.PubSub.subscribe(Matdori.PubSub, room_topic(post.id))
      Phoenix.PubSub.subscribe(Matdori.PubSub, presence_topic(post.id))

      Presence.track(self(), presence_topic(post.id), socket.assigns.session_id, %{
        display_name: socket.assigns.display_name,
        color: socket.assigns.color,
        avatar_url: socket.assigns.avatar_url,
        cursor: %{x: 0, y: 0},
        cursor_note_text: "",
        cursor_note_mode: "clear",
        cursor_note_updated_at_ms: 0,
        overlay_highlight_draft: nil
      })
    end

    socket
  end

  defp maybe_unsubscribe_from_previous_topics(socket, next_post) do
    previous_post_id = socket.assigns.post && socket.assigns.post.id
    next_post_id = next_post && next_post.id

    if connected?(socket) and previous_post_id && previous_post_id != next_post_id do
      Phoenix.PubSub.unsubscribe(Matdori.PubSub, room_topic(previous_post_id))
      Phoenix.PubSub.unsubscribe(Matdori.PubSub, presence_topic(previous_post_id))
    end

    socket
  end

  defp resolve_snapshot(post, nil), do: post.current_snapshot

  defp resolve_snapshot(post, version) when is_integer(version) do
    Collab.get_snapshot(post.id, version)
  end

  defp resolve_snapshot(post, version) do
    case Integer.parse(version) do
      {parsed, ""} -> Collab.get_snapshot(post.id, parsed)
      _ -> post.current_snapshot
    end
  end

  defp build_segments(text, highlights) when is_binary(text) do
    graphemes = String.graphemes(text)
    sorted = Enum.sort_by(highlights, & &1.start_g)

    {segments, cursor} =
      Enum.reduce(sorted, {[], 0}, fn highlight, {acc, cursor} ->
        plain =
          if highlight.start_g > cursor, do: slice(graphemes, cursor, highlight.start_g), else: ""

        selected = slice(graphemes, highlight.start_g, highlight.end_g)

        next_acc =
          acc
          |> maybe_push_plain(plain)
          |> Kernel.++([%{type: :highlight, text: selected, highlight: highlight}])

        {next_acc, highlight.end_g}
      end)

    tail =
      if cursor < length(graphemes), do: slice(graphemes, cursor, length(graphemes)), else: ""

    maybe_push_plain(segments, tail)
  end

  defp display_title(post) do
    case String.trim(post.title || "") do
      "" -> "Untitled Share"
      title -> title
    end
  end

  defp preview_description(post) do
    case String.trim(post.preview_description || "") do
      "" ->
        case String.trim(post.preview_title || "") do
          "" -> "OG preview description is unavailable."
          title -> title
        end

      value ->
        value
    end
  end

  defp preview_image_url(post) do
    case String.trim(post.preview_image_url || "") do
      "" -> nil
      value -> normalize_preview_image_url(value)
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

  defp preview_source(post) do
    case URI.parse(String.trim(post.tweet_url || "")) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> "source unavailable"
    end
  end

  defp preview_card(assigns) do
    ~H"""
    <div id="link-preview-card" class="overflow-hidden rounded-xl border border-slate-200 bg-white">
      <a
        id="preview-card-source"
        href={@post.tweet_url}
        target="_blank"
        rel="noopener noreferrer"
        class="block transition hover:bg-slate-50"
      >
        <div class="aspect-[16/9] w-full bg-zinc-100">
          <img
            :if={preview_image_url(@post)}
            id="preview-card-image"
            src={preview_image_url(@post)}
            alt={display_title(@post)}
            class="h-full w-full object-cover"
            loading="lazy"
            referrerpolicy="no-referrer"
          />
          <div :if={!preview_image_url(@post)} class="flex h-full items-center justify-center">
            <div class="space-y-1 px-3 text-left">
              <p class="line-clamp-1 text-xs font-bold text-slate-900">{display_title(@post)}</p>
              <p class="line-clamp-2 text-[11px] text-slate-600">{preview_description(@post)}</p>
              <p class="line-clamp-1 text-[10px] text-slate-500">{preview_source(@post)}</p>
            </div>
          </div>
        </div>
        <div class="space-y-1.5 p-3">
          <p class="truncate text-sm font-bold text-slate-900">{display_title(@post)}</p>
          <p class="text-xs leading-relaxed text-slate-600">{preview_description(@post)}</p>
        </div>
      </a>
    </div>
    """
  end

  defp participant_count(presences) when is_map(presences), do: map_size(presences)
  defp participant_count(_), do: 0

  defp maybe_assign_presence_members(socket, presence_members) do
    if socket.assigns.presence_members == presence_members do
      socket
    else
      assign(socket, :presence_members, presence_members)
    end
  end

  defp presence_members_from_presences(presences) when is_map(presences) do
    Map.new(presences, fn {session_id, presence} ->
      meta = presence_meta(presence)

      {session_id,
       %{
         display_name: normalize_display_name(meta),
         color: normalize_hex_color(meta_color(meta), "#64748b"),
         avatar_url: normalize_avatar_url(meta_avatar_url(meta), nil)
       }}
    end)
  end

  defp presence_members_from_presences(_presences), do: %{}

  defp presence_label(presence, session_id, my_session_id) do
    label = normalize_display_name(presence)

    if session_id == my_session_id do
      "#{label} (me)"
    else
      label
    end
  end

  defp presence_color(presence) do
    normalize_hex_color(meta_color(presence), "#64748b")
  end

  defp presence_avatar_url(presence) do
    normalize_avatar_url(meta_avatar_url(presence), nil)
  end

  defp presence_avatar_initial(presence, session_id, my_session_id) do
    presence
    |> presence_label(session_id, my_session_id)
    |> String.replace(" (me)", "")
    |> String.trim()
    |> String.first()
    |> case do
      nil -> "?"
      value -> String.upcase(value)
    end
  end

  defp unique_cursor_color(_session_id, fallback) when is_binary(fallback) do
    normalize_hex_color(fallback, "#3b82f6")
  end

  defp unique_cursor_color(session_id, _fallback)
       when is_binary(session_id) and session_id != "" do
    hue = :erlang.phash2(session_id, 360) / 360
    hsl_to_hex(hue, 0.72, 0.52)
  end

  defp unique_cursor_color(_session_id, _fallback), do: "#3b82f6"

  defp normalize_hex_color(value, default) do
    if is_binary(value) and Regex.match?(~r/^#[0-9a-fA-F]{6}$/, value) do
      value
    else
      default
    end
  end

  defp hsl_to_hex(h, s, l) do
    {r, g, b} = hsl_to_rgb(h, s, l)

    "#" <>
      Enum.map_join([r, g, b], fn channel ->
        channel
        |> round()
        |> max(0)
        |> min(255)
        |> Integer.to_string(16)
        |> String.pad_leading(2, "0")
      end)
  end

  defp hsl_to_rgb(_h, s, l) when s <= 0, do: {l * 255, l * 255, l * 255}

  defp hsl_to_rgb(h, s, l) do
    q = if l < 0.5, do: l * (1 + s), else: l + s - l * s
    p = 2 * l - q

    {
      255 * hue_to_rgb(p, q, h + 1 / 3),
      255 * hue_to_rgb(p, q, h),
      255 * hue_to_rgb(p, q, h - 1 / 3)
    }
  end

  defp hue_to_rgb(p, q, t) when t < 0, do: hue_to_rgb(p, q, t + 1)
  defp hue_to_rgb(p, q, t) when t > 1, do: hue_to_rgb(p, q, t - 1)

  defp hue_to_rgb(p, q, t) do
    cond do
      t < 1 / 6 -> p + (q - p) * 6 * t
      t < 1 / 2 -> q
      t < 2 / 3 -> p + (q - p) * (2 / 3 - t) * 6
      true -> p
    end
  end

  defp normalize_display_name(data) do
    case data do
      %{display_name: name} when is_binary(name) and name != "" -> String.slice(name, 0, 30)
      %{"display_name" => name} when is_binary(name) and name != "" -> String.slice(name, 0, 30)
      _ -> "Guest"
    end
  end

  defp meta_color(data) do
    case data do
      %{color: value} -> value
      %{"color" => value} -> value
      _ -> nil
    end
  end

  defp meta_avatar_url(data) do
    case data do
      %{avatar_url: value} -> value
      %{"avatar_url" => value} -> value
      _ -> nil
    end
  end

  defp normalize_avatar_url(value, default) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      normalize_avatar_url(default, nil)
    else
      trimmed
    end
  end

  defp normalize_avatar_url(_value, default) when is_binary(default),
    do: normalize_avatar_url(default, nil)

  defp normalize_avatar_url(_value, _default), do: nil

  defp comment_avatar_url(
         comment,
         presence_members,
         my_session_id,
         my_avatar_url,
         profile_overrides
       ) do
    profile_avatar_url =
      case resolved_identity(google_uid_from(comment), profile_overrides) do
        %{avatar_url: value} when is_binary(value) and value != "" -> value
        _ -> nil
      end

    cond do
      is_binary(my_avatar_url) and my_avatar_url != "" and comment.session_id == my_session_id ->
        my_avatar_url

      is_map(presence_members) ->
        case Map.get(presence_members, comment.session_id) do
          nil -> profile_avatar_url
          presence -> presence_avatar_url(presence)
        end

      is_binary(profile_avatar_url) and profile_avatar_url != "" ->
        profile_avatar_url

      true ->
        nil
    end
  end

  defp resolved_comment_display_name(comment, profile_overrides) do
    identity = resolved_identity(google_uid_from(comment), profile_overrides)
    identity.display_name || normalize_display_name(comment)
  end

  defp resolved_comment_color(comment, profile_overrides) do
    identity = resolved_identity(google_uid_from(comment), profile_overrides)
    identity.color || normalize_hex_color(meta_color(comment), "#64748b")
  end

  defp profile_overrides_for(
         room_comments,
         highlights,
         overlay_highlights,
         overlay_highlight_comments
       ) do
    google_uids =
      room_comments
      |> collect_google_uids_from_identity_source()
      |> Kernel.++(collect_google_uids_from_identity_source(highlights))
      |> Kernel.++(collect_google_uids_from_identity_source(overlay_highlights))
      |> Kernel.++(collect_google_uids_from_identity_source(overlay_highlight_comments))
      |> Enum.uniq()

    Collab.list_profiles_by_google_uids(google_uids)
  end

  defp collect_google_uids_from_identity_source(entries) when is_list(entries) do
    entries
    |> Enum.map(&google_uid_from/1)
    |> Enum.reject(&is_nil/1)
  end

  defp collect_google_uids_from_identity_source(_entries), do: []

  defp google_uid_from(data) do
    case data do
      %{google_uid: uid} when is_binary(uid) and uid != "" -> uid
      %{"google_uid" => uid} when is_binary(uid) and uid != "" -> uid
      _ -> nil
    end
  end

  defp resolved_identity(nil, _profile_overrides),
    do: %{display_name: nil, color: nil, avatar_url: nil}

  defp resolved_identity(google_uid, profile_overrides) when is_map(profile_overrides) do
    case Map.get(profile_overrides, google_uid) do
      %{display_name: _name, color: _color, avatar_url: _avatar} = profile -> profile
      _ -> %{display_name: nil, color: nil, avatar_url: nil}
    end
  end

  defp resolved_identity(_google_uid, _profile_overrides),
    do: %{display_name: nil, color: nil, avatar_url: nil}

  defp meta_cursor(data) do
    case data do
      %{cursor: value} when is_map(value) -> value
      %{"cursor" => value} when is_map(value) -> value
      _ -> %{x: 0, y: 0}
    end
  end

  defp upsert_presence_meta(socket, update_fun) when is_function(update_fun, 1) do
    post_id = socket.assigns.post.id
    topic = presence_topic(post_id)
    session_id = socket.assigns.session_id

    next_meta =
      socket
      |> current_presence_meta(topic, session_id)
      |> update_fun.()
      |> normalize_presence_meta(socket)

    Presence.update(self(), topic, session_id, next_meta)
  end

  defp current_presence_meta(socket, topic, session_id) do
    case Presence.list(topic) do
      %{^session_id => %{metas: [meta | _]}} -> meta
      _ -> base_presence_meta(socket)
    end
  end

  defp base_presence_meta(socket) do
    %{
      display_name: socket.assigns.display_name,
      color: socket.assigns.color,
      avatar_url: socket.assigns.avatar_url,
      cursor: %{x: 0, y: 0},
      cursor_note_text: "",
      cursor_note_mode: "clear",
      cursor_note_updated_at_ms: 0,
      overlay_highlight_draft: nil
    }
  end

  defp normalize_presence_meta(meta, socket) do
    mode =
      normalize_cursor_note_mode(
        meta_cursor_note_mode(meta),
        normalize_cursor_note_text(meta_cursor_note_text(meta))
      )

    %{
      display_name: normalize_display_name(meta),
      color: normalize_hex_color(meta_color(meta), socket.assigns.color),
      avatar_url: normalize_avatar_url(meta_avatar_url(meta), socket.assigns.avatar_url),
      cursor: normalize_cursor_position(meta_cursor_x(meta), meta_cursor_y(meta), %{x: 0, y: 0}),
      cursor_note_text: normalize_cursor_note_text(meta_cursor_note_text(meta)),
      cursor_note_mode: mode,
      cursor_note_updated_at_ms:
        normalize_cursor_note_updated_at_ms(meta_cursor_note_updated_at_ms(meta)),
      overlay_highlight_draft:
        normalize_overlay_highlight_zone(meta_overlay_highlight_draft(meta))
    }
  end

  defp normalize_cursor_position(raw_x, raw_y, fallback) do
    %{
      x:
        normalize_cursor_coordinate(raw_x, normalize_cursor_coordinate(Map.get(fallback, :x), 0)),
      y: normalize_cursor_coordinate(raw_y, normalize_cursor_coordinate(Map.get(fallback, :y), 0))
    }
  end

  defp normalize_cursor_coordinate(value, _default) when is_integer(value), do: max(value, 0)
  defp normalize_cursor_coordinate(value, _default) when is_float(value), do: max(round(value), 0)

  defp normalize_cursor_coordinate(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> max(parsed, 0)
      _ -> default
    end
  end

  defp normalize_cursor_coordinate(_value, default), do: default

  defp login_required_reply(socket) do
    {:noreply,
     socket
     |> put_flash(:error, "Only signed-in users can edit.")
     |> push_navigate(to: ~p"/login")}
  end

  defp logged_in?(session) when is_map(session) do
    case session["google_uid"] do
      uid when is_binary(uid) and uid != "" -> true
      _ -> false
    end
  end

  defp logged_in?(_session), do: false

  defp normalize_cursor_note_text(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.slice(0, @cursor_note_max_len)
  end

  defp normalize_cursor_note_text(_value), do: ""

  defp normalize_cursor_note_mode(raw_mode, normalized_text) do
    mode =
      case raw_mode do
        "typing" -> "typing"
        "final" -> "final"
        "clear" -> "clear"
        _ -> "typing"
      end

    if normalized_text == "" do
      "clear"
    else
      mode
    end
  end

  defp meta_cursor_x(data), do: meta_cursor(data) |> Map.get(:x) || meta_cursor(data)["x"]
  defp meta_cursor_y(data), do: meta_cursor(data) |> Map.get(:y) || meta_cursor(data)["y"]

  defp meta_cursor_note_text(data) do
    case data do
      %{cursor_note_text: value} -> value
      %{"cursor_note_text" => value} -> value
      _ -> ""
    end
  end

  defp meta_cursor_note_mode(data) do
    case data do
      %{cursor_note_mode: value} -> value
      %{"cursor_note_mode" => value} -> value
      _ -> "clear"
    end
  end

  defp meta_cursor_note_updated_at_ms(data) do
    case data do
      %{cursor_note_updated_at_ms: value} -> value
      %{"cursor_note_updated_at_ms" => value} -> value
      _ -> 0
    end
  end

  defp meta_overlay_highlight_draft(data) do
    case data do
      %{overlay_highlight_draft: value} -> value
      %{"overlay_highlight_draft" => value} -> value
      _ -> nil
    end
  end

  defp normalize_overlay_highlight_zone(zone) when is_map(zone) do
    with {:ok, left} <- normalize_overlay_ratio(Map.get(zone, :left) || Map.get(zone, "left")),
         {:ok, top} <- normalize_overlay_ratio(Map.get(zone, :top) || Map.get(zone, "top")),
         {:ok, width} <- normalize_overlay_ratio(Map.get(zone, :width) || Map.get(zone, "width")),
         {:ok, height} <-
           normalize_overlay_ratio(Map.get(zone, :height) || Map.get(zone, "height")) do
      max_width = max(1.0 - left, 0.0)
      max_height = max(1.0 - top, 0.0)
      safe_width = min(width, max_width)
      safe_height = min(height, max_height)

      if safe_width > 0.0 and safe_height > 0.0 do
        id =
          normalize_overlay_highlight_id(
            Map.get(zone, :id) || Map.get(zone, "id"),
            left,
            top,
            safe_width,
            safe_height
          )

        comment =
          normalize_overlay_highlight_comment(Map.get(zone, :comment) || Map.get(zone, "comment"))

        %{left: left, top: top, width: safe_width, height: safe_height, id: id, comment: comment}
      else
        nil
      end
    else
      :error -> nil
    end
  end

  defp normalize_overlay_highlight_zone(_zone), do: nil

  defp normalize_overlay_ratio(value) when is_integer(value) do
    {:ok, clamp_overlay_ratio(value * 1.0)}
  end

  defp normalize_overlay_ratio(value) when is_float(value) do
    {:ok, clamp_overlay_ratio(value)}
  end

  defp normalize_overlay_ratio(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, clamp_overlay_ratio(parsed)}
      _ -> :error
    end
  end

  defp normalize_overlay_ratio(_value), do: :error

  defp clamp_overlay_ratio(value) do
    rounded = Float.round(value, 4)

    cond do
      rounded < 0.0 -> 0.0
      rounded > 1.0 -> 1.0
      true -> rounded
    end
  end

  defp normalize_overlay_highlight_id(value, left, top, width, height)
       when is_binary(value) and value != "" do
    value
    |> String.trim()
    |> String.slice(0, 80)
    |> case do
      "" -> deterministic_overlay_highlight_id(left, top, width, height)
      trimmed -> trimmed
    end
  end

  defp normalize_overlay_highlight_id(_value, left, top, width, height),
    do: deterministic_overlay_highlight_id(left, top, width, height)

  defp deterministic_overlay_highlight_id(left, top, width, height) do
    hash =
      :crypto.hash(:sha256, "#{left}:#{top}:#{width}:#{height}")
      |> Base.encode16(case: :lower)

    "hl-" <> String.slice(hash, 0, 16)
  end

  defp normalize_overlay_highlight_comment(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.slice(0, 240)
  end

  defp normalize_overlay_highlight_comment(_value), do: ""

  defp normalize_cursor_note_updated_at_ms(value) when is_integer(value), do: max(value, 0)

  defp normalize_cursor_note_updated_at_ms(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} -> max(parsed, 0)
      _ -> 0
    end
  end

  defp normalize_cursor_note_updated_at_ms(_value), do: 0

  defp presence_meta(%{metas: [meta | _]}), do: meta
  defp presence_meta(%{"metas" => [meta | _]}), do: meta
  defp presence_meta(_), do: %{}

  defp embed_provider(post), do: Embed.classify(post.tweet_url).provider
  defp youtube_embed_url(post), do: Embed.classify(post.tweet_url).embed_url
  defp embed_status_label(post), do: post.tweet_url |> Embed.classify() |> Embed.status_label()

  defp maybe_push_plain(segments, ""), do: segments
  defp maybe_push_plain(segments, text), do: segments ++ [%{type: :plain, text: text}]

  defp room_metrics(post_id) do
    %{
      like_count: Collab.reaction_count(post_id, "like"),
      dislike_count: Collab.reaction_count(post_id, "dislike"),
      view_count: Collab.view_count(post_id)
    }
  end

  defp comment_profile_initial(display_name) when is_binary(display_name) do
    display_name
    |> String.trim()
    |> String.slice(0, 1)
    |> case do
      "" -> "G"
      initial -> String.upcase(initial)
    end
  end

  defp comment_profile_initial(_), do: "G"

  defp format_comment_time(%DateTime{} = inserted_at) do
    inserted_at
    |> Calendar.strftime("%Y.%m.%d %H:%M")
  end

  defp format_comment_time(_), do: ""

  defp slice(graphemes, start_g, end_g) do
    graphemes
    |> Enum.slice(start_g, max(end_g - start_g, 0))
    |> Enum.join()
  end

  defp broadcast_refresh(socket) do
    if socket.assigns.post do
      broadcast_room_refresh(socket.assigns.post.id)
    end
  end

  defp broadcast_room_refresh(post_id) when is_integer(post_id) do
    Phoenix.PubSub.broadcast(
      Matdori.PubSub,
      room_topic(post_id),
      {:room_refresh, post_id}
    )
  end

  defp broadcast_room_refresh(_post_id), do: :ok

  defp broadcast_room_metrics(post_id, metrics) when is_integer(post_id) and is_map(metrics) do
    Phoenix.PubSub.broadcast(
      Matdori.PubSub,
      room_topic(post_id),
      {:room_metrics, post_id, metrics}
    )
  end

  defp broadcast_room_metrics(_post_id, _metrics), do: :ok

  defp broadcast_overlay_highlights(post_id) when is_integer(post_id) do
    Phoenix.PubSub.broadcast(
      Matdori.PubSub,
      room_topic(post_id),
      {:overlay_highlights_updated, post_id}
    )
  end

  defp broadcast_overlay_highlights(_post_id), do: :ok

  defp push_overlay_highlight_states(socket, overlay_highlights, overlay_highlight_comments) do
    presence_members = socket.assigns[:presence_members] || %{}
    my_session_id = socket.assigns[:session_id]
    my_avatar_url = socket.assigns[:avatar_url]
    profile_overrides = socket.assigns[:profile_overrides] || %{}

    socket
    |> push_event("overlay_highlights_state", %{
      highlights: overlay_highlights_payload(overlay_highlights, profile_overrides)
    })
    |> push_event("overlay_highlight_comments_state", %{
      comments:
        overlay_highlight_comments_payload(
          overlay_highlight_comments,
          presence_members,
          my_session_id,
          my_avatar_url,
          profile_overrides
        )
    })
  end

  defp overlay_highlights_payload(highlights, profile_overrides) when is_list(highlights) do
    Enum.map(highlights, fn highlight ->
      identity = resolved_identity(google_uid_from(highlight), profile_overrides)

      %{
        session_id: highlight.session_id,
        display_name: identity.display_name || highlight.display_name,
        color: identity.color || highlight.color,
        profile_url: user_profile_path_from(highlight),
        id: highlight.highlight_key,
        left: highlight.left,
        top: highlight.top,
        width: highlight.width,
        height: highlight.height,
        comment: highlight.comment || ""
      }
    end)
  end

  defp overlay_highlights_payload(_, _), do: []

  defp overlay_highlight_comments_payload(
         comments,
         presence_members,
         my_session_id,
         my_avatar_url,
         profile_overrides
       )
       when is_list(comments) do
    Enum.map(comments, fn comment ->
      identity = resolved_identity(google_uid_from(comment), profile_overrides)

      %{
        id: comment.id,
        highlight_id: comment.highlight_id,
        session_id: comment.session_id,
        display_name: identity.display_name || comment.display_name,
        color: identity.color || comment.color,
        profile_url: user_profile_path_from(comment),
        body: comment.body,
        avatar_url:
          comment_avatar_url_from_session(
            comment.session_id,
            presence_members,
            my_session_id,
            my_avatar_url,
            identity.avatar_url
          ),
        inserted_at:
          case comment.inserted_at do
            %DateTime{} = inserted_at -> DateTime.to_iso8601(inserted_at)
            _ -> nil
          end
      }
    end)
  end

  defp overlay_highlight_comments_payload(_, _, _, _, _), do: []

  defp user_profile_path_from(data) do
    case google_uid_from(data) do
      uid when is_binary(uid) and uid != "" -> ~p"/users/#{uid}"
      _ -> nil
    end
  end

  defp comment_avatar_url_from_session(
         session_id,
         presence_members,
         my_session_id,
         my_avatar_url,
         profile_avatar_url
       )
       when is_binary(session_id) do
    cond do
      is_binary(my_avatar_url) and my_avatar_url != "" and session_id == my_session_id ->
        my_avatar_url

      is_map(presence_members) ->
        case Map.get(presence_members, session_id) do
          nil -> profile_avatar_url
          presence -> presence_avatar_url(presence)
        end

      is_binary(profile_avatar_url) and profile_avatar_url != "" ->
        profile_avatar_url

      true ->
        nil
    end
  end

  defp comment_avatar_url_from_session(
         _session_id,
         _presence_members,
         _my_session_id,
         _my_avatar_url,
         _profile_avatar_url
       ),
       do: nil

  defp room_topic(post_id), do: "room:#{post_id}"
  defp presence_topic(post_id), do: "presence:#{post_id}"
end
