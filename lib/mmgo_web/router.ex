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
    live "/play", GameEntryLive
    post "/auth/telegram", TelegramAuthController, :create
    get "/play/new", PlayDemoController, :new
    get "/play/continue", PlayDemoController, :continue
    get "/demo/start", PlayDemoController, :start

    live_session :game, on_mount: [{MMGOWeb.GameAuth, :require_character}] do
      live "/map", MapLive
      live "/notifications", NotificationsLive
      live "/spellbook", SpellbookLive
      live "/pvp", DuelLive
      live "/screens", ScreensIndexLive

      live "/academy/bulletin-board", BulletinBoardLive
      live "/academy/study-desk", AcademyLive, :overview
      live "/academy/lecture/:term_id", LectureLive
      live "/academy/exam/:term_id", ExamLive
      live "/academy/club-events/:event_id", ClubEventLive

      live "/orgs", OrganizationsLive, :index
      live "/orgs/new", OrganizationsLive, :new
      live "/orgs/:id", OrganizationsLive, :show
      live "/orgs/:id/:tab", OrganizationsLive, :show

      live "/event", ActionHubLive
      live "/travel", TravelLive
      live "/party", PartyLive
      live "/combat", CombatLive, :current
      live "/combat/:id", CombatLive, :show
      live "/defeat", DefeatLive
      live "/base", BaseLive, :index
      live "/base/:id", BaseLive, :show
      live "/trade", TradeLive
      live "/inventory", InventoryLive
      live "/alchemy", AlchemyLive
      live "/craft", CraftLive
      live "/finance", FinanceLive
      live "/dungeon", DungeonLive, :depths
      live "/dungeon/level/:level", DungeonLive, :level

      live "/academy", AcademyLive, :overview
      live "/academy/timetable", AcademyLive, :timetable
      live "/academy/grades", AcademyLive, :grades
      live "/academy/library", AcademyLive, :library
      live "/academy/courses", AcademyLive, :courses
      live "/academy/progress", AcademyLive, :progress
      live "/academy/clubs", ClubsLive, :index
      live "/academy/clubs/:id", ClubsLive, :show
      live "/academy/clubs/:id/manage", ClubsLive, :manage
      live "/academy/research", AcademiaLive
      live "/academy/thesis/:id", ThesisDefenseLive
    end

    live_session :realm_migration,
      on_mount: [{MMGOWeb.GameAuth, :require_migration_character}] do
      live "/realms", RealmsLive
    end
  end

  scope "/", MMGOWeb do
    pipe_through :api

    get "/healthz", HealthController, :show
    get "/livez", HealthController, :live
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
    post "/reset", PlayDemoController, :reset
    post "/demo/reset", PlayDemoController, :reset
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
      live "/screens", ScreensIndexLive
    end

    scope "/", MMGOWeb do
      pipe_through :browser

      live "/editor", MapEditorLive
    end
  end
end
