defmodule MatdoriWeb.MyPageLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab

  @profile_tabs ~w(created highlighted liked)

  @impl true
  def mount(_params, session, socket) do
    google_uid = session["google_uid"]
    session_id = session["session_id"]
    session_display_name = session["display_name"]
    email = session["google_email"]
    avatar_url = session["google_avatar"]

    profile = Collab.get_profile_by_google_uid(google_uid)
    display_name = profile.display_name || session_display_name || "프로필"

    {:ok,
     socket
     |> assign(:google_uid, google_uid)
     |> assign(:session_id, session_id)
     |> assign(:session_display_name, session_display_name)
     |> assign(:display_name, display_name)
     |> assign(:email, email)
     |> assign(:avatar_url, avatar_url)
     |> assign(:active_tab, "created")
     |> assign(:editing_profile, false)
     |> assign(:interests, profile.interests || [])
     |> assign(:profile_form, profile_form(display_name, profile.interests || []))
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
        "프로필"

    {:noreply,
     socket
     |> reload_profile_lists()
     |> assign(:display_name, display_name)
     |> assign(:interests, profile.interests || [])
     |> assign(:profile_form, profile_form(display_name, profile.interests || []))}
  end

  @impl true
  def handle_event("open_profile_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_profile, true)
     |> assign(:profile_form, profile_form(socket.assigns.display_name, socket.assigns.interests))}
  end

  @impl true
  def handle_event("close_profile_edit", _params, socket) do
    {:noreply, assign(socket, :editing_profile, false)}
  end

  @impl true
  def handle_event("save_profile", %{"profile" => params}, socket) do
    display_name = String.trim(params["display_name"] || "")
    interests = parse_interests(params["interests_input"] || "")

    cond do
      display_name == "" ->
        {:noreply,
         socket
         |> assign(:profile_form, profile_form(display_name, interests))
         |> put_flash(:error, "사용자 이름을 입력해 주세요")}

      true ->
        case Collab.upsert_profile_by_google_uid(socket.assigns.google_uid, %{
               display_name: display_name,
               interests: interests
             }) do
          {:ok, profile} ->
            saved_name = profile.display_name || display_name
            saved_interests = profile.interests || []

            {:noreply,
             socket
             |> assign(:display_name, saved_name)
             |> assign(:interests, saved_interests)
             |> assign(:editing_profile, false)
             |> assign(:profile_form, profile_form(saved_name, saved_interests))
             |> put_flash(:info, "프로필이 저장되었습니다")}

          {:error, _} ->
            {:noreply,
             socket
             |> assign(:profile_form, profile_form(display_name, interests))
             |> put_flash(:error, "프로필을 저장할 수 없습니다")}
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={
        %{display_name: @display_name, email: @email, avatar_url: @avatar_url, authenticated: true}
      }
      topbar={%{mode: :profile, refresh_event: "refresh_profile_topbar"}}
    >
      <section id="my-page" class="space-y-4">
        <section id="my-profile-header" class="mat-surface p-5 sm:p-7">
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
                {@display_name || "프로필"}
              </h1>
              <p :if={@email} id="my-profile-email" class="text-sm text-slate-500">{@email}</p>

              <div id="my-profile-interest" class="my-profile-interest">
                <%= for interest <- @interests do %>
                  <span class="mat-pill my-interest-chip">{interest}</span>
                <% end %>
              </div>
            </div>

            <button
              id="my-profile-edit-toggle"
              type="button"
              class="mat-btn-secondary my-profile-edit-btn"
              phx-click="open_profile_edit"
            >
              프로필 편집
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
              내방
            </button>
            <button
              id="my-tab-highlighted"
              type="button"
              phx-click="switch_profile_tab"
              phx-value-tab="highlighted"
              class={profile_tab_class(@active_tab == "highlighted")}
            >
              하이라이트방
            </button>
            <button
              id="my-tab-liked"
              type="button"
              phx-click="switch_profile_tab"
              phx-value-tab="liked"
              class={profile_tab_class(@active_tab == "liked")}
            >
              좋아요방
            </button>
          </div>
        </section>

        <div :if={@editing_profile} id="my-profile-edit-modal" class="my-profile-modal-backdrop">
          <div class="my-profile-modal-card" phx-click-away="close_profile_edit">
            <div class="my-profile-modal-head">
              <h2 class="text-lg font-black tracking-tight text-slate-900">프로필 편집</h2>
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
              phx-submit="save_profile"
            >
              <.input
                id="my-profile-name-input"
                field={@profile_form[:display_name]}
                type="text"
                label="사용자 이름"
                required
              />
              <.input
                id="my-profile-interests-input"
                field={@profile_form[:interests_input]}
                type="text"
                label="관심 분야"
                placeholder="예: AI, 스타트업, 제품 디자인"
              />
              <p class="my-profile-modal-help">쉼표(,)로 구분하면 여러 개를 입력할 수 있어요.</p>

              <div class="my-profile-modal-actions">
                <button
                  id="my-profile-cancel"
                  type="button"
                  class="mat-btn-secondary"
                  phx-click="close_profile_edit"
                >
                  취소
                </button>
                <button id="my-profile-save" type="submit" class="mat-btn-primary">
                  저장
                </button>
              </div>
            </.form>
          </div>
        </div>

        <section :if={@active_tab == "created"} id="my-created-rooms" class="mat-surface p-6 sm:p-7">
          <h2 class="text-xl font-black tracking-tight text-slate-900">내가 만든 방</h2>
          <%= if @created_posts == [] do %>
            <p id="my-created-empty" class="mt-3 text-sm text-slate-500">아직 생성한 방이 없습니다.</p>
          <% else %>
            <div class="mt-4 space-y-2.5">
              <%= for post <- @created_posts do %>
                <.link
                  id={"my-created-room-#{post.id}"}
                  navigate={~p"/rooms/#{post.id}"}
                  class="mat-card block p-3"
                >
                  <p class="truncate text-sm font-bold text-slate-900">{display_title(post)}</p>
                  <p class="mt-1 truncate text-xs text-slate-500">{post.tweet_url}</p>
                </.link>
              <% end %>
            </div>
          <% end %>
        </section>

        <section
          :if={@active_tab == "highlighted"}
          id="my-highlighted-rooms"
          class="mat-surface p-6 sm:p-7"
        >
          <h2 class="text-xl font-black tracking-tight text-slate-900">내가 하이라이트한 방</h2>
          <%= if @highlighted_posts == [] do %>
            <p id="my-highlighted-empty" class="mt-3 text-sm text-slate-500">하이라이트한 방이 없습니다.</p>
          <% else %>
            <div class="mt-4 space-y-2.5">
              <%= for post <- @highlighted_posts do %>
                <.link
                  id={"my-highlighted-room-#{post.id}"}
                  navigate={~p"/rooms/#{post.id}"}
                  class="mat-card block p-3"
                >
                  <p class="truncate text-sm font-bold text-slate-900">{display_title(post)}</p>
                  <p class="mt-1 truncate text-xs text-slate-500">{post.tweet_url}</p>
                </.link>
              <% end %>
            </div>
          <% end %>
        </section>

        <section :if={@active_tab == "liked"} id="my-liked-rooms" class="mat-surface p-6 sm:p-7">
          <h2 class="text-xl font-black tracking-tight text-slate-900">내가 좋아요한 방</h2>
          <%= if @liked_posts == [] do %>
            <p id="my-liked-empty" class="mt-3 text-sm text-slate-500">좋아요한 방이 없습니다.</p>
          <% else %>
            <div class="mt-4 space-y-2.5">
              <%= for post <- @liked_posts do %>
                <.link
                  id={"my-liked-room-#{post.id}"}
                  navigate={~p"/rooms/#{post.id}"}
                  class="mat-card block p-3"
                >
                  <p class="truncate text-sm font-bold text-slate-900">{display_title(post)}</p>
                  <p class="mt-1 truncate text-xs text-slate-500">{post.tweet_url}</p>
                </.link>
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
      "" -> "제목 없는 공유"
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

  defp profile_form(display_name, interests) do
    to_form(
      %{
        "display_name" => display_name || "",
        "interests_input" => Enum.join(interests || [], ", ")
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
end
