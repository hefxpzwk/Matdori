defmodule MatdoriWeb.RoomLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.RateLimiter
  alias MatdoriWeb.Presence

  @cursor_limit 20
  @action_limit 20

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:session_id, session["session_id"])
      |> assign(:display_name, session["display_name"])
      |> assign(:color, session["color"])
      |> assign(:post, nil)
      |> assign(:snapshot, nil)
      |> assign(:snapshot_versions, [])
      |> assign(:selected_version, nil)
      |> assign(:segments, [])
      |> assign(:highlights, [])
      |> assign(:selected_highlight_id, nil)
      |> assign(:heart_count, 0)
      |> assign(:hearted, false)
      |> assign(:presences, %{})
      |> assign(:privacy_notice_open, true)
      |> assign(:room_identifier, :latest)
      |> assign(:room_path, ~p"/rooms/latest")
      |> assign(:post_list, [])
      |> assign(:source_account, Application.get_env(:matdori, :x_source_username))

    {:ok, load_room(socket, :latest)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    room_identifier = room_identifier_from_params(params, socket.assigns.live_action)
    version = Map.get(params, "v")
    socket = maybe_sync_from_x(socket, room_identifier)

    {:noreply, load_room(socket, room_identifier, version)}
  end

  @impl true
  def handle_event("change_version", %{"version" => version}, socket) do
    {:noreply, push_patch(socket, to: room_path_with_version(socket.assigns.room_path, version))}
  end

  def handle_event("cursor_move", %{"x" => x, "y" => y}, socket) do
    if RateLimiter.allow?(socket.assigns.session_id, :cursor_move, @cursor_limit, :second) == :ok and
         socket.assigns.post do
      Presence.update(
        self(),
        presence_topic(socket.assigns.post.id),
        socket.assigns.session_id,
        %{
          cursor: %{x: x, y: y},
          display_name: socket.assigns.display_name,
          color: socket.assigns.color
        }
      )
    end

    {:noreply, socket}
  end

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

  def handle_event("toggle_heart", _params, socket) do
    with :ok <- RateLimiter.allow?(socket.assigns.session_id, :toggle_heart, @action_limit),
         %{id: post_id} <- socket.assigns.post,
         {:ok, _} <- Collab.toggle_heart(post_id, socket.assigns.session_id) do
      broadcast_refresh(socket)
      {:noreply, reload_current_room(socket)}
    else
      {:error, :rate_limited} ->
        {:noreply, put_flash(socket, :error, "너무 빠르게 클릭하고 있습니다.")}

      _ ->
        {:noreply, put_flash(socket, :error, "하트 상태를 변경할 수 없습니다.")}
    end
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

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    if socket.assigns.post do
      presences = Presence.list(presence_topic(socket.assigns.post.id))

      {:noreply,
       push_event(socket, "presence_state", %{presences: presences, me: socket.assigns.session_id})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={%{}}>
      <section class="space-y-4" id="today-room">
        <%= if @post do %>
          <article class="rounded-2xl border border-zinc-200 bg-white p-4 shadow-sm">
            <div class="mb-3 flex items-center justify-between">
              <h1 class="text-lg font-semibold text-zinc-900">
                {if @room_identifier == :latest, do: "최신 포스트", else: "아카이브 포스트"}
              </h1>
              <a
                id="tweet-link"
                href={@post.tweet_url}
                target="_blank"
                rel="noopener noreferrer"
                class="text-sm font-medium text-blue-700 underline"
              >
                X 원문 보기
              </a>
            </div>

            <%= if @post.hidden do %>
              <div
                id="takedown-state"
                class="rounded-lg border border-rose-200 bg-rose-50 p-3 text-rose-800"
              >
                콘텐츠를 볼 수 없습니다.
              </div>
            <% else %>
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
              <p class="mt-2 text-xs text-zinc-500">
                임베드가 로드되지 않으면 위의 원문 링크를 이용해 주세요.
              </p>
            <% end %>
          </article>
        <% else %>
          <div
            id="empty-state"
            class="rounded-2xl border border-zinc-200 bg-white p-6 text-zinc-700 shadow-sm"
          >
            아직 표시할 포스트가 없습니다. X_BEARER_TOKEN 설정을 확인하거나 관리자 페이지에서 포스트를 생성해 주세요.
          </div>
        <% end %>
      </section>
    </Layouts.app>
    """
  end

  defp load_room(socket, room_identifier, selected_version \\ nil) do
    case fetch_post(room_identifier) do
      nil ->
        socket
        |> maybe_unsubscribe_from_previous_topics(nil)
        |> assign(:room_identifier, room_identifier)
        |> assign(:room_path, room_path(room_identifier))
        |> assign(:post_list, Collab.list_posts())
        |> assign(:post, nil)
        |> assign(:snapshot, nil)
        |> assign(:snapshot_versions, [])
        |> assign(:selected_version, nil)
        |> assign(:segments, [])
        |> assign(:highlights, [])
        |> assign(:heart_count, 0)
        |> assign(:hearted, false)
        |> assign(:presences, %{})

      post ->
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
        |> assign(:post_list, Collab.list_posts())
        |> assign(:post, post)
        |> assign(:snapshot, active_snapshot)
        |> assign(:snapshot_versions, Enum.map(post.snapshots, & &1.version))
        |> assign(:selected_version, active_snapshot && active_snapshot.version)
        |> assign(:highlights, highlights)
        |> assign(
          :segments,
          build_segments((active_snapshot && active_snapshot.normalized_text) || "", highlights)
        )
        |> assign(:heart_count, Collab.heart_count(post.id))
        |> assign(:hearted, Collab.hearted_by?(post.id, socket.assigns.session_id))
        |> assign(:presences, presences)
        |> push_event("presence_state", %{presences: presences, me: socket.assigns.session_id})
    end
  end

  defp reload_current_room(socket) do
    load_room(socket, socket.assigns.room_identifier, socket.assigns.selected_version)
  end

  defp room_identifier_from_params(%{"post_id" => post_id}, _live_action) do
    case Integer.parse(post_id) do
      {parsed, ""} -> {:post, parsed}
      _ -> :latest
    end
  end

  defp room_identifier_from_params(_params, _live_action), do: :latest

  defp fetch_post(:latest), do: Collab.get_latest_post_with_versions()
  defp fetch_post({:post, post_id}), do: Collab.get_post_with_versions(post_id)

  defp room_path(:latest), do: ~p"/rooms/latest"
  defp room_path({:post, post_id}), do: ~p"/rooms/#{post_id}"

  defp room_path_with_version(path, version), do: path <> "?v=#{version}"

  defp maybe_sync_from_x(socket, :latest) do
    case RateLimiter.allow?("system:x-sync", :sync_latest_posts, 1, :minute) do
      :ok ->
        case Collab.sync_configured_account_posts(session_id: socket.assigns.session_id) do
          {:ok, _summary} -> socket
          {:error, :missing_x_bearer_token} -> socket
          {:error, :missing_x_source_username} -> socket
          {:error, _reason} -> socket
        end

      {:error, :rate_limited} ->
        socket
    end
  end

  defp maybe_sync_from_x(socket, _room_identifier), do: socket

  defp maybe_subscribe_to_topics(socket, post) do
    previous_post_id = socket.assigns.post && socket.assigns.post.id

    if connected?(socket) and previous_post_id != post.id do
      Phoenix.PubSub.subscribe(Matdori.PubSub, room_topic(post.id))
      Phoenix.PubSub.subscribe(Matdori.PubSub, presence_topic(post.id))

      Presence.track(self(), presence_topic(post.id), socket.assigns.session_id, %{
        display_name: socket.assigns.display_name,
        color: socket.assigns.color,
        cursor: %{x: 0, y: 0}
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

  defp maybe_push_plain(segments, ""), do: segments
  defp maybe_push_plain(segments, text), do: segments ++ [%{type: :plain, text: text}]

  defp slice(graphemes, start_g, end_g) do
    graphemes
    |> Enum.slice(start_g, max(end_g - start_g, 0))
    |> Enum.join()
  end

  defp broadcast_refresh(socket) do
    if socket.assigns.post do
      Phoenix.PubSub.broadcast(
        Matdori.PubSub,
        room_topic(socket.assigns.post.id),
        {:room_refresh, socket.assigns.post.id}
      )
    end
  end

  defp room_topic(post_id), do: "room:#{post_id}"
  defp presence_topic(post_id), do: "presence:#{post_id}"
end
