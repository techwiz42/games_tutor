defmodule GamesTutorWeb.AuthPipeline do
  use Guardian.Plug.Pipeline,
    otp_app: :games_tutor,
    module: GamesTutor.Guardian,
    error_handler: GamesTutorWeb.AuthErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
end
