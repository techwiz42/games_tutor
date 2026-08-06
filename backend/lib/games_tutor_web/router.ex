defmodule GamesTutorWeb.Router do
  use GamesTutorWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug GamesTutorWeb.AuthPipeline
  end

  scope "/api/auth", GamesTutorWeb do
    pipe_through :api

    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/refresh", AuthController, :refresh
    post "/logout", AuthController, :logout
    post "/confirm-email", AuthController, :confirm_email
    post "/resend-confirmation", AuthController, :resend_confirmation
    post "/forgot-password", AuthController, :forgot_password
    post "/reset-password", AuthController, :reset_password
    get "/google/authorize", AuthController, :google_authorize
    get "/google/callback", AuthController, :google_callback
  end

  scope "/api/auth", GamesTutorWeb do
    pipe_through [:api, :authenticated]

    get "/me", AuthController, :me
  end

  scope "/api/games", GamesTutorWeb do
    pipe_through [:api, :authenticated]

    get "/", GameController, :index
    post "/", GameController, :create
    get "/:id", GameController, :show
    post "/:id/moves", GameController, :create_move
    post "/:id/resign", GameController, :resign
  end

  scope "/api", GamesTutorWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:games_tutor, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: GamesTutorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
