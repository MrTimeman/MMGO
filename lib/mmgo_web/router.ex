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

  pipeline :browser_api do
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", MMGOWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/play", PlayLive
    live "/base", BaseLive
    live "/academy", AcademyLive
    live "/spells", SpellListLive
    live "/spellbook", SpellListLive
    live "/spells/new", SpellNewLive
    live "/grimoires", GrimoireLive
    live "/combat/:id", CombatLive
    live "/operator/map", OperatorMapLive

    live "/academy/bulletin-board", BulletinBoardLive
    live "/academy/study-desk", StudyDeskLive
    live "/academy/exam/:term_id", ExamLive
    live "/academy/club-events/:event_id", ClubEventLive
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

  scope "/api/play", MMGOWeb do
    pipe_through :browser_api

    get "/state", PlayApiController, :state
    post "/journeys", PlayApiController, :create_journey
    post "/journey-plans", PlayApiController, :create_journey_plan
    post "/telegram-session", PlayApiController, :telegram_session
    post "/utility-spells", PlayApiController, :cast_utility_spell
    post "/demo/reset", PlayDemoController, :reset
    post "/demo/arrive", PlayApiController, :fast_arrive
  end

  scope "/api/operator/map", MMGOWeb do
    pipe_through :browser_api

    post "/locations", OperatorMapApiController, :create_location
    post "/routes", OperatorMapApiController, :create_route
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
