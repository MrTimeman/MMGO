defmodule MMGOWeb.Router do
  use MMGOWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MMGOWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MMGOWeb do
    pipe_through :browser

    live "/", TelegramEntryLive
    get "/bootstrap", PageController, :home
  end

  scope "/", MMGOWeb do
    pipe_through :api

    get "/healthz", HealthController, :show
  end

  scope "/api", MMGOWeb do
    pipe_through :api

    post "/telegram/webhook", TelegramWebhookController, :create
    get "/federation/realm-manifest", FederationController, :manifest
    post "/federation/import-migration", FederationController, :import_migration
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:mmgo, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev", MMGOWeb do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MMGOWeb.Telemetry
      live "/hooks", HooksDemoLive
    end
  end
end
