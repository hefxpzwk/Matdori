defmodule MatdoriWeb.Router do
  use MatdoriWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug MatdoriWeb.Plugs.Identity
    plug :fetch_live_flash
    plug :put_root_layout, html: {MatdoriWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MatdoriWeb.Plugs.ContentSecurityPolicy
  end

  pipeline :require_google_auth do
    plug MatdoriWeb.Plugs.RequireGoogleAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MatdoriWeb do
    pipe_through :browser

    get "/login", AuthController, :login
    post "/auth/logout", AuthController, :logout
    get "/auth/:provider", AuthController, :request
    get "/auth/:provider/callback", AuthController, :callback
    post "/auth/:provider/callback", AuthController, :callback
  end

  scope "/", MatdoriWeb do
    pipe_through :browser

    live "/", ShareLive, :index
    live "/rooms", RoomIndexLive, :index
    live "/rooms/:post_id", RoomLive, :show
    live "/users/:google_uid", UserProfileLive, :show
  end

  scope "/", MatdoriWeb do
    pipe_through [:browser, :require_google_auth]

    live "/me", MyPageLive, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", MatdoriWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:matdori, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MatdoriWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
