defmodule MatdoriWeb.RoomLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.Embed
  alias Matdori.RateLimiter
  alias MatdoriWeb.Presence

  @cursor_limit 20
  @cursor_note_limit 30
  @cursor_note_max_len 80
  @overlay_highlight_limit 40
  @overlay_draft_limit 30
  @action_limit 20

  @impl true
  def mount(_params, session, socket) do
    session_id = session["session_id"]
    display_name = session["display_name"]
    color = unique_cursor_color(session_id, session["color"])

    socket =
      socket
      |> assign(:session_id, session_id)
      |> assign(:display_name, display_name)
      |> assign(:color, color)
      |> assign(:post, nil)
      |> assign(:snapshot, nil)
      |> assign(:snapshot_versions, [])
      |> assign(:selected_version, nil)
      |> assign(:segments, [])
      |> assign(:highlights, [])
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
         |> put_flash(:error, "방을 찾을 수 없습니다")
         |> push_navigate(to: ~p"/rooms")}
    end
  end

  @impl true
  def handle_event("change_version", %{"version" => version}, socket) do
    {:noreply, push_patch(socket, to: room_path_with_version(socket.assigns.room_path, version))}
  end

  def handle_event("cursor_move", %{"x" => x, "y" => y}, socket) do
    if RateLimiter.allow?(socket.assigns.session_id, :cursor_move, @cursor_limit, :second) == :ok and
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
    if RateLimiter.allow?(socket.assigns.session_id, :cursor_note, @cursor_note_limit, :second) ==
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
    if RateLimiter.allow?(
         socket.assigns.session_id,
         :overlay_highlights_sync,
         @action_limit,
         :second
       ) == :ok and socket.assigns.post do
      upsert_presence_meta(socket, fn meta ->
        meta
        |> Map.put(:overlay_highlights, normalize_overlay_highlights(highlights))
        |> Map.put(:overlay_highlight_draft, nil)
      end)
    end

    {:noreply, socket}
  end

  def handle_event("overlay_highlight_draft", %{"zone" => zone}, socket) do
    if RateLimiter.allow?(
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

  def handle_event("select_highlight", %{"highlight_id" => id}, socket) do
    case Integer.parse(id) do
      {parsed, ""} -> {:noreply, assign(socket, :selected_highlight_id, parsed)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("create_highlight", params, socket) do
    with :ok <- RateLimiter.allow?(socket.assigns.session_id, :create_highlight, @action_limit),
         %{id: _} = snapshot <- socket.assigns.snapshot,
         {:ok, _highlight} <-
           Collab.create_highlight(
             snapshot,
             Map.merge(params, %{
               "session_id" => socket.assigns.session_id,
               "display_name" => socket.assigns.display_name,
               "color" => socket.assigns.color
             })
           ) do
      broadcast_refresh(socket)
      {:noreply, reload_current_room(socket)}
    else
      {:error, :overlap} ->
        {:noreply, put_flash(socket, :error, "이미 존재하는 하이라이트와 선택 영역이 겹칩니다.")}

      {:error, :ambiguous} ->
        {:noreply, put_flash(socket, :error, "선택 영역이 모호합니다. 더 구체적인 구문을 선택해 주세요.")}

      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "하이라이트 요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "하이라이트를 생성할 수 없습니다.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("comment_submit", %{"comment" => %{"body" => body}}, socket) do
    with :ok <- RateLimiter.allow?(socket.assigns.session_id, :comment_submit, @action_limit),
         selected when is_integer(selected) <- socket.assigns.selected_highlight_id,
         {:ok, _comment} <-
           Collab.create_comment(selected, %{
             "session_id" => socket.assigns.session_id,
             "display_name" => socket.assigns.display_name,
             "body" => body
           }) do
      broadcast_refresh(socket)
      {:noreply, reload_current_room(socket)}
    else
      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "댓글 요청이 너무 많습니다. 잠시만 기다려 주세요.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "댓글을 저장할 수 없습니다.")}

      _ ->
        {:noreply, put_flash(socket, :error, "먼저 하이라이트를 선택해 주세요.")}
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    with :ok <- RateLimiter.allow?(socket.assigns.session_id, :delete_comment, @action_limit),
         {parsed, ""} <- Integer.parse(id),
         {:ok, _} <- Collab.soft_delete_comment(parsed, socket.assigns.session_id) do
      broadcast_refresh(socket)
      {:noreply, reload_current_room(socket)}
    else
      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, "본인이 최근에 작성한 댓글만 삭제할 수 있습니다.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "댓글을 삭제할 수 없습니다.")}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_reaction", %{"kind" => kind}, socket) do
    with :ok <- RateLimiter.allow?(socket.assigns.session_id, :toggle_reaction, @action_limit),
         %{id: post_id} <- socket.assigns.post,
         {:ok, _} <- Collab.toggle_reaction(post_id, socket.assigns.session_id, kind) do
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
      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "너무 빠르게 클릭하고 있습니다.")}

      {:error, :invalid_reaction_kind} ->
        {:noreply, put_flash(socket, :error, "지원하지 않는 반응입니다.")}

      _ ->
        {:noreply, put_flash(socket, :error, "하트 상태를 변경할 수 없습니다.")}
    end
  end

  def handle_event("toggle_heart", _params, socket) do
    handle_event("toggle_reaction", %{"kind" => "like"}, socket)
  end

  def handle_event("submit_report", %{"report" => %{"reason" => reason}}, socket) do
    with :ok <- RateLimiter.allow?(socket.assigns.session_id, :report, 5),
         %{id: post_id} <- socket.assigns.post,
         {:ok, _} <-
           Collab.create_report(post_id, %{
             "session_id" => socket.assigns.session_id,
             "display_name" => socket.assigns.display_name,
             "reason" => reason
           }) do
      {:noreply, put_flash(socket, :info, "신고가 접수되었습니다. 감사합니다.")}
    else
      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "현재 신고 한도에 도달했습니다.")}

      _ ->
        {:noreply, put_flash(socket, :error, "신고를 제출할 수 없습니다.")}
    end
  end

  def handle_event("update_name", %{"profile" => %{"display_name" => name}}, socket) do
    cleaned =
      name
      |> String.trim()
      |> String.replace(~r/[^\p{L}\p{N}\s_-]/u, "")
      |> String.slice(0, 30)

    if cleaned == "" do
      {:noreply, put_flash(socket, :error, "표시 이름은 비워둘 수 없습니다.")}
    else
      if socket.assigns.post do
        upsert_presence_meta(
          assign(socket, :display_name, cleaned),
          &Map.put(&1, :display_name, cleaned)
        )
      end

      {:noreply,
       socket
       |> assign(:display_name, cleaned)
       |> put_flash(:info, "이 세션의 표시 이름이 변경되었습니다.")}
    end
  end

  def handle_event("dismiss_privacy", _params, socket) do
    {:noreply, assign(socket, :privacy_notice_open, false)}
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
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="space-y-4" id="room-detail">
        <.link
          id="back-to-room-list"
          navigate={~p"/rooms"}
          class="inline-flex rounded-lg border border-zinc-300 px-3 py-1 text-sm text-zinc-700 hover:bg-zinc-50"
        >
          방 목록으로
        </.link>

        <%= if @post do %>
          <article
            id="room-collab-stage"
            phx-hook="SnapshotCanvas"
            data-cursor-color={@color}
            class="relative rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm"
          >
            <div class="mb-3 flex items-center justify-between">
              <div class="flex items-center gap-2">
                <h1 id="room-title" class="text-lg font-semibold text-zinc-900">
                  {display_title(@post)}
                </h1>
                <span
                  id="room-embed-status"
                  class="rounded-full border border-zinc-300 px-2 py-0.5 text-xs font-medium text-zinc-600"
                >
                  {embed_status_label(@post)}
                </span>
              </div>
              <a
                id="tweet-link"
                href={@post.tweet_url}
                target="_blank"
                rel="noopener noreferrer"
                class="text-sm font-medium text-blue-700 underline"
              >
                원문 보기
              </a>
            </div>

            <div
              id="room-presence-panel"
              class="mb-3 rounded-xl border border-zinc-200 bg-zinc-50 p-3"
            >
              <p
                id="room-presence-count"
                aria-live="polite"
                class="text-sm font-semibold text-zinc-800"
              >
                현재 접속 {participant_count(@presence_members)}명
              </p>
              <div id="room-presence-list" class="mt-2 flex flex-wrap items-center gap-2">
                <span
                  :for={{session_id, presence} <- @presence_members}
                  id={"room-presence-user-#{session_id}"}
                  class="inline-flex items-center gap-2 rounded-full border border-zinc-300 bg-white px-2.5 py-1 text-xs text-zinc-700"
                >
                  <span
                    class="h-2.5 w-2.5 rounded-full"
                    style={"background-color: #{presence_color(presence)}"}
                  >
                  </span>
                  {presence_label(presence, session_id, @session_id)}
                </span>
              </div>
            </div>

            <div id="room-reactions" class="mb-3 flex items-center gap-2">
              <button
                id="like-button"
                type="button"
                phx-click="toggle_reaction"
                phx-value-kind="like"
                class={[
                  "inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-sm font-medium transition",
                  if(@liked,
                    do: "border-emerald-300 bg-emerald-50 text-emerald-700",
                    else: "border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50"
                  )
                ]}
              >
                <.icon name="hero-hand-thumb-up" class="h-4 w-4" /> 좋아요
                <span id="like-count">{@like_count}</span>
              </button>

              <button
                id="dislike-button"
                type="button"
                phx-click="toggle_reaction"
                phx-value-kind="dislike"
                class={[
                  "inline-flex items-center gap-1 rounded-full border px-3 py-1.5 text-sm font-medium transition",
                  if(@disliked,
                    do: "border-rose-300 bg-rose-50 text-rose-700",
                    else: "border-zinc-300 bg-white text-zinc-700 hover:bg-zinc-50"
                  )
                ]}
              >
                <.icon name="hero-hand-thumb-down" class="h-4 w-4" /> 싫어요
                <span id="dislike-count">{@dislike_count}</span>
              </button>

              <span
                id="room-view-count"
                class="inline-flex items-center gap-1 rounded-full border border-zinc-300 bg-white px-3 py-1.5 text-sm font-medium text-zinc-700"
              >
                조회수 {@view_count}
              </span>
            </div>

            <%= if @post.hidden do %>
              <div
                id="takedown-state"
                class="rounded-lg border border-rose-200 bg-rose-50 p-3 text-rose-800"
              >
                콘텐츠를 볼 수 없습니다.
              </div>
            <% else %>
              <div id="embed-highlight-controls" class="mb-3 flex flex-wrap items-center gap-2">
                <button
                  id="embed-highlight-mode-toggle"
                  type="button"
                  data-highlight-overlay-toggle
                  class="inline-flex items-center gap-1 rounded-full border border-zinc-300 bg-white px-3 py-1.5 text-sm font-medium text-zinc-700 transition hover:bg-zinc-50"
                >
                  <.icon name="hero-pencil-square" class="h-4 w-4" /> 하이라이트 선택 모드
                </button>
                <button
                  id="embed-highlight-clear"
                  type="button"
                  data-highlight-overlay-clear
                  class="inline-flex items-center gap-1 rounded-full border border-zinc-300 bg-white px-3 py-1.5 text-sm font-medium text-zinc-700 transition hover:bg-zinc-50"
                >
                  <.icon name="hero-trash" class="h-4 w-4" /> 선택 초기화
                </button>
                <span
                  id="embed-highlight-count"
                  class="inline-flex items-center rounded-full border border-amber-200 bg-amber-50 px-3 py-1 text-xs font-semibold text-amber-700"
                >
                  0개 선택됨
                </span>
              </div>

              <div id="room-embed-stage" class="relative isolate">
                <%= if embed_provider(@post) == :x do %>
                  <div class="space-y-2">
                    <div
                      id="tweet-embed"
                      phx-hook="XEmbed"
                      phx-update="ignore"
                      data-tweet-url={@post.tweet_url}
                      class="min-h-24 rounded-lg border border-zinc-100 bg-zinc-50 p-2"
                    >
                      <blockquote class="twitter-tweet">
                        <a href={@post.tweet_url}>X 게시글</a>
                      </blockquote>
                    </div>
                    <p class="text-xs text-zinc-500">
                      임베드가 로드되지 않으면 위의 원문 링크를 이용해 주세요.
                    </p>
                  </div>
                <% else %>
                  <%= if embed_provider(@post) == :youtube do %>
                    <div class="overflow-hidden rounded-lg border border-zinc-200 bg-zinc-50">
                      <iframe
                        id="youtube-embed"
                        src={youtube_embed_url(@post)}
                        class="w-full"
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
                    <div
                      id="link-preview-card"
                      class="overflow-hidden rounded-lg border border-zinc-200 bg-white"
                    >
                      <a
                        id="preview-card-source"
                        href={@post.tweet_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        class="block hover:bg-zinc-50"
                      >
                        <div class="aspect-[16/9] w-full bg-zinc-100">
                          <img
                            :if={preview_image_url(@post)}
                            id="preview-card-image"
                            src={preview_image_url(@post)}
                            alt={display_title(@post)}
                            class="h-full w-full object-cover"
                            loading="lazy"
                          />
                          <div
                            :if={!preview_image_url(@post)}
                            class="flex h-full items-center justify-center text-xs text-zinc-500"
                          >
                            이미지 없음
                          </div>
                        </div>
                        <div class="space-y-1 p-3">
                          <p class="truncate text-sm font-semibold text-zinc-900">
                            {display_title(@post)}
                          </p>
                          <p class="text-xs text-zinc-600">{preview_description(@post)}</p>
                          <p class="truncate text-[11px] text-zinc-500">{@post.tweet_url}</p>
                        </div>
                      </a>
                    </div>
                  <% end %>
                <% end %>

                <div
                  id="room-embed-highlight-overlay"
                  phx-hook="EmbedHighlightOverlay"
                  phx-update="ignore"
                  data-stage-selector="#room-embed-stage"
                  data-toggle-selector="#embed-highlight-mode-toggle"
                  data-clear-selector="#embed-highlight-clear"
                  data-count-selector="#embed-highlight-count"
                  data-session-id={@session_id}
                  data-user-color={@color}
                  class="pointer-events-none absolute inset-0 z-10 overflow-hidden rounded-lg"
                >
                </div>
              </div>
            <% end %>

            <div
              id="room-remote-cursors"
              phx-hook="RemoteCursors"
              phx-update="ignore"
              class="pointer-events-none absolute inset-0 z-20 overflow-hidden rounded-2xl"
            >
            </div>
          </article>
        <% else %>
          <div
            id="empty-state"
            class="rounded-2xl border border-zinc-200 bg-white p-6 text-zinc-700 shadow-sm"
          >
            방을 찾을 수 없습니다. 방 목록에서 다시 선택해 주세요.
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

  defp maybe_subscribe_to_topics(socket, post) do
    previous_post_id = socket.assigns.post && socket.assigns.post.id

    if connected?(socket) and previous_post_id != post.id do
      Phoenix.PubSub.subscribe(Matdori.PubSub, room_topic(post.id))
      Phoenix.PubSub.subscribe(Matdori.PubSub, presence_topic(post.id))

      Presence.track(self(), presence_topic(post.id), socket.assigns.session_id, %{
        display_name: socket.assigns.display_name,
        color: socket.assigns.color,
        cursor: %{x: 0, y: 0},
        cursor_note_text: "",
        cursor_note_mode: "clear",
        cursor_note_updated_at_ms: 0,
        overlay_highlights: [],
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
      "" -> "제목 없는 공유"
      title -> title
    end
  end

  defp preview_description(post) do
    case String.trim(post.preview_description || "") do
      "" -> "원문 링크를 열어 자세한 내용을 확인하세요."
      value -> value
    end
  end

  defp preview_image_url(post) do
    case String.trim(post.preview_image_url || "") do
      "" -> nil
      value -> value
    end
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
         color: normalize_hex_color(meta_color(meta), "#64748b")
       }}
    end)
  end

  defp presence_members_from_presences(_presences), do: %{}

  defp presence_label(presence, session_id, my_session_id) do
    label = normalize_display_name(presence)

    if session_id == my_session_id do
      "#{label} (나)"
    else
      label
    end
  end

  defp presence_color(presence) do
    normalize_hex_color(meta_color(presence), "#64748b")
  end

  defp unique_cursor_color(session_id, _fallback)
       when is_binary(session_id) and session_id != "" do
    hue = :erlang.phash2(session_id, 360) / 360
    hsl_to_hex(hue, 0.72, 0.52)
  end

  defp unique_cursor_color(_session_id, fallback), do: normalize_hex_color(fallback, "#3b82f6")

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
      cursor: %{x: 0, y: 0},
      cursor_note_text: "",
      cursor_note_mode: "clear",
      cursor_note_updated_at_ms: 0,
      overlay_highlights: [],
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
      cursor: normalize_cursor_position(meta_cursor_x(meta), meta_cursor_y(meta), %{x: 0, y: 0}),
      cursor_note_text: normalize_cursor_note_text(meta_cursor_note_text(meta)),
      cursor_note_mode: mode,
      cursor_note_updated_at_ms:
        normalize_cursor_note_updated_at_ms(meta_cursor_note_updated_at_ms(meta)),
      overlay_highlights: normalize_overlay_highlights(meta_overlay_highlights(meta)),
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

  defp meta_overlay_highlights(data) do
    case data do
      %{overlay_highlights: value} -> value
      %{"overlay_highlights" => value} -> value
      _ -> []
    end
  end

  defp meta_overlay_highlight_draft(data) do
    case data do
      %{overlay_highlight_draft: value} -> value
      %{"overlay_highlight_draft" => value} -> value
      _ -> nil
    end
  end

  defp normalize_overlay_highlights(value) when is_list(value) do
    value
    |> Enum.reduce([], fn zone, acc ->
      case normalize_overlay_highlight_zone(zone) do
        nil -> acc
        normalized -> [normalized | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.take(@overlay_highlight_limit)
  end

  defp normalize_overlay_highlights(_value), do: []

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
        %{left: left, top: top, width: safe_width, height: safe_height}
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

  defp room_topic(post_id), do: "room:#{post_id}"
  defp presence_topic(post_id), do: "presence:#{post_id}"
end
