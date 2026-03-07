defmodule MatdoriWeb.ShareLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab
  alias Matdori.RateLimiter

  @action_limit 20

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
     |> assign(:share_form, empty_share_form())}
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

  defp logged_in?(session) when is_map(session) do
    case session["google_uid"] do
      uid when is_binary(uid) and uid != "" -> true
      _ -> false
    end
  end

  defp logged_in?(_session), do: false
end
