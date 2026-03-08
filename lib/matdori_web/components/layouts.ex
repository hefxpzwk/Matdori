defmodule MatdoriWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MatdoriWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :topbar, :map,
    default: %{mode: :default},
    doc: "topbar configuration"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:authenticated, scope_authenticated(assigns[:current_scope]))
      |> assign(:display_name, scope_display_name(assigns[:current_scope]))
      |> assign(:email, scope_email(assigns[:current_scope]))
      |> assign(:avatar_url, scope_avatar_url(assigns[:current_scope]))
      |> assign(:accent_color, scope_color(assigns[:current_scope]))
      |> assign(:topbar_mode, topbar_mode(assigns[:topbar]))
      |> assign(:topbar_title, topbar_title(assigns[:topbar]))
      |> assign(:topbar_refresh_event, topbar_refresh_event(assigns[:topbar]))

    ~H"""
    <div class="mat-shell min-h-screen" style={"--mat-accent: #{@accent_color};"}>
      <section class="mx-auto h-full w-full max-w-[1320px] px-3 sm:px-4">
        <div class="x-home-grid x-home-grid--wide">
          <aside id="x-left-rail" class="x-left-rail">
            <a href="/" class="x-rail-logo">
              <img src={~p"/images/logo.svg"} width="22" />
            </a>

            <div class="x-rail-main">
              <nav class="x-rail-nav" aria-label="Main">
                <a href={~p"/"} class="x-rail-nav-item">
                  <.icon name="hero-home-solid" class="size-5" /> 홈
                </a>
                <a href={~p"/rooms"} class="x-rail-nav-item">
                  <.icon name="hero-magnifying-glass" class="size-5" /> 탐색하기
                </a>
                <a href={~p"/rooms"} class="x-rail-nav-item">
                  <.icon name="hero-bell" class="size-5" /> 알림
                </a>
                <a :if={@authenticated and @display_name} href={~p"/me"} class="x-rail-nav-item">
                  <.icon name="hero-user" class="size-5" /> 프로필
                </a>
              </nav>

              <.link id="left-create-room" navigate={~p"/"} class="x-rail-post-btn">
                방 만들기
              </.link>
            </div>

            <div :if={@authenticated and @display_name} class="x-rail-bottom">
              <button
                id="left-profile-trigger"
                type="button"
                class="x-profile-trigger"
                phx-click={JS.toggle(to: "#left-profile-menu")}
              >
                <span class="x-profile-avatar">
                  <img
                    :if={@avatar_url}
                    src={@avatar_url}
                    alt="profile"
                    class="x-profile-avatar-image"
                  />
                  <.icon :if={!@avatar_url} name="hero-user" class="size-4" />
                </span>
                <span class="x-profile-meta">
                  <span id="header-display-name" class="x-profile-name">{@display_name}</span>
                  <span :if={@email} class="x-profile-email">{@email}</span>
                </span>
                <.icon name="hero-chevron-up-down" class="size-4 text-slate-500" />
              </button>

              <div
                id="left-profile-menu"
                class="x-profile-menu hidden"
                phx-click-away={JS.hide(to: "#left-profile-menu")}
              >
                <.link navigate={~p"/me"} class="x-profile-menu-item">
                  <.icon name="hero-cog-6-tooth" class="size-4" /> 설정
                </.link>
                <a href={~p"/auth/logout"} class="x-profile-menu-item danger">
                  <.icon name="hero-arrow-right-start-on-rectangle" class="size-4" /> 로그아웃
                </a>
              </div>
            </div>

            <a
              :if={!(@authenticated and @display_name)}
              href={~p"/login"}
              class="mat-btn-primary x-rail-login"
            >
              로그인
            </a>
          </aside>

          <main id="x-main-column" class="x-main-column">
            <header :if={@topbar_mode == :default} class="x-main-topbar">
              <a href={~p"/"} class="x-main-tab">추천</a>
              <a href={~p"/rooms"} class="x-main-tab">검색</a>
            </header>

            <header :if={@topbar_mode == :room} class="x-main-topbar x-main-topbar--room">
              <button
                id="room-topbar-back"
                type="button"
                class="x-room-topbar-back"
                phx-click={JS.dispatch("matdori:history-back")}
              >
                <.icon name="hero-arrow-left" class="size-5" />
              </button>
              <button
                id="room-topbar-title"
                type="button"
                class="x-room-topbar-title"
                phx-click={@topbar_refresh_event}
              >
                {@topbar_title}
              </button>
            </header>

            <header :if={@topbar_mode == :profile} class="x-main-topbar x-main-topbar--profile">
              <button
                id="profile-topbar-back"
                type="button"
                class="x-profile-topbar-back"
                phx-click={JS.dispatch("matdori:history-back")}
              >
                <.icon name="hero-arrow-left" class="size-5" />
              </button>
              <button
                id="profile-topbar-title"
                type="button"
                class="x-profile-topbar-title"
                phx-click={@topbar_refresh_event}
              >
                프로필
              </button>
            </header>

            <div class="x-page-content">
              {render_slot(@inner_block)}
            </div>
          </main>
        </div>
      </section>

      <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc false
  def theme_toggle(assigns) do
    ~H"""
    <div></div>
    """
  end

  defp scope_display_name(%{display_name: name}) when is_binary(name) and name != "" do
    name
  end

  defp scope_display_name(%{"display_name" => name}) when is_binary(name) and name != "" do
    name
  end

  defp scope_display_name(_), do: nil

  defp scope_email(%{email: email}) when is_binary(email) and email != "", do: email
  defp scope_email(%{"email" => email}) when is_binary(email) and email != "", do: email
  defp scope_email(_), do: nil

  defp scope_avatar_url(%{avatar_url: url}) when is_binary(url) and url != "", do: url
  defp scope_avatar_url(%{"avatar_url" => url}) when is_binary(url) and url != "", do: url
  defp scope_avatar_url(_), do: nil

  defp scope_color(%{color: color}) when is_binary(color), do: normalize_color(color)
  defp scope_color(%{"color" => color}) when is_binary(color), do: normalize_color(color)
  defp scope_color(_), do: "#3b82f6"

  defp topbar_mode(%{mode: :room}), do: :room
  defp topbar_mode(%{mode: :profile}), do: :profile
  defp topbar_mode(_), do: :default

  defp topbar_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp topbar_title(_), do: "방"

  defp topbar_refresh_event(%{refresh_event: event}) when is_binary(event) and event != "",
    do: event

  defp topbar_refresh_event(_), do: nil

  defp scope_authenticated(%{authenticated: true}), do: true
  defp scope_authenticated(%{"authenticated" => true}), do: true
  defp scope_authenticated(_), do: false

  defp normalize_color(value) do
    trimmed = String.trim(value)

    if Regex.match?(~r/^#[0-9a-fA-F]{6}$/, trimmed) do
      String.downcase(trimmed)
    else
      "#3b82f6"
    end
  end
end
