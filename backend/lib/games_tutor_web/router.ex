defmodule GamesTutorWeb.Router do
  use GamesTutorWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug GamesTutorWeb.AuthPipeline
    plug GamesTutorWeb.RejectBanned
  end

  pipeline :admin do
    plug GamesTutorWeb.RequireAdmin
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
    post "/:id/undo", GameController, :undo
    delete "/:id", GameController, :delete
    get "/:id/board-state", GameController, :board_state
    get "/:id/move-analysis", GameController, :move_analysis
    post "/:id/hint", GameController, :hint
  end

  scope "/api/skill-profiles", GamesTutorWeb do
    pipe_through [:api, :authenticated]

    get "/", SkillProfileController, :index
  end

  scope "/api/user-settings", GamesTutorWeb do
    pipe_through [:api, :authenticated]

    get "/", UserSettingsController, :show
    patch "/", UserSettingsController, :update
  end

  scope "/api/voice", GamesTutorWeb do
    pipe_through [:api, :authenticated]

    post "/session", VoiceController, :create
    post "/session/:id/end", VoiceController, :end_session
  end

  scope "/api/admin", GamesTutorWeb do
    pipe_through [:api, :authenticated, :admin]

    get "/users", AdminController, :index
    post "/users/:id/ban", AdminController, :ban
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
