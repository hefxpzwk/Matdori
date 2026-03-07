defmodule MatdoriWeb.MyPageLive do
  use MatdoriWeb, :live_view

  alias Matdori.Collab

  @impl true
  def mount(_params, session, socket) do
    google_uid = session["google_uid"]
    session_id = session["session_id"]
    display_name = session["display_name"]
    email = session["google_email"]
    avatar_url = session["google_avatar"]

    {:ok,
     socket
     |> assign(:display_name, display_name)
     |> assign(:email, email)
     |> assign(:avatar_url, avatar_url)
     |> assign(:created_posts, Collab.list_created_posts_by_google_uid(google_uid))
     |> assign(:liked_posts, Collab.list_liked_posts_by_google_uid(google_uid))
     |> assign(:highlighted_posts, Collab.list_highlighted_posts_for_user(google_uid, session_id))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={
        %{display_name: @display_name, email: @email, avatar_url: @avatar_url, authenticated: true}
      }
    >
      <section id="my-page" class="space-y-4">
        <section id="my-created-rooms" class="mat-surface p-6 sm:p-7">
          <h1 class="text-xl font-black tracking-tight text-slate-900">내가 만든 방</h1>
          <p class="mt-1 text-sm text-slate-600">Google 계정으로 생성한 방 목록입니다.</p>
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

        <section id="my-liked-rooms" class="mat-surface p-6 sm:p-7">
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

        <section id="my-highlighted-rooms" class="mat-surface p-6 sm:p-7">
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
end
