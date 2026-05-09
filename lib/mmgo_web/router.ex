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
    get "/play", PlayController, :show
    get "/play/editor", PlayController, :editor
  end

  scope "/", MMGOWeb do
    pipe_through :api

    get "/healthz", HealthController, :show
  end

  scope "/api/auth", MMGOWeb do
    pipe_through :browser_api

    post "/telegram", TelegramAuthController, :create
  end

  scope "/api/play", MMGOWeb do
    pipe_through :browser_api

    get "/hub", PlayApiController, :hub
    get "/state", PlayApiController, :state
    post "/journeys", PlayApiController, :create_journey
    post "/utility-spells", PlayApiController, :cast_utility_spell
    get "/characters/search", PlayApiController, :search_characters
    get "/spells", PlayApiController, :list_spells
    post "/spells", PlayApiController, :create_spell
    post "/duels", PlayApiController, :create_duel
    get "/dungeons/state", PlayApiController, :dungeon_state
    post "/dungeons/enter", PlayApiController, :enter_dungeon
    post "/dungeons/move", PlayApiController, :move_in_dungeon
    post "/dungeons/fight", PlayApiController, :fight_encounter
    post "/dungeons/harvest", PlayApiController, :harvest_resource
    post "/dungeons/claim-loot", PlayApiController, :claim_loot
    post "/dungeons/extract", PlayApiController, :extract_dungeon
    post "/dungeons/return-ritual", PlayApiController, :return_ritual
    post "/party/leave", PlayApiController, :leave_party
    post "/demo/reset", PlayDemoController, :reset
  end

  scope "/api/play/admin", MMGOWeb do
    pipe_through :browser_api

    post "/locations", PlayAdminController, :create_location
    put "/locations/:id", PlayAdminController, :update_location
    delete "/locations/:id", PlayAdminController, :delete_location

    post "/routes", PlayAdminController, :create_route
    put "/routes/:id", PlayAdminController, :update_route
    delete "/routes/:id", PlayAdminController, :delete_route
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:mmgo, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev", MMGOWeb do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MMGOWeb.Telemetry
    end
  end
end
