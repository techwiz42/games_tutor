defmodule GamesTutorWeb.FallbackController do
  use GamesTutorWeb, :controller

  def call(conn, {:error, :bad_request}) do
    conn |> put_status(:bad_request) |> json(%{detail: "Missing required fields"})
  end

  def call(conn, {:error, :invalid_credentials}) do
    conn |> put_status(:unauthorized) |> json(%{detail: "Invalid email or password"})
  end

  def call(conn, {:error, :not_confirmed}) do
    conn
    |> put_status(:forbidden)
    |> json(%{detail: "Please confirm your email before logging in", code: "not_confirmed"})
  end

  def call(conn, {:error, :invalid}) do
    conn |> put_status(:unauthorized) |> json(%{detail: "Invalid refresh token"})
  end

  def call(conn, {:error, :expired}) do
    conn |> put_status(:unauthorized) |> json(%{detail: "Refresh token expired"})
  end

  def call(conn, {:error, :revoked}) do
    conn |> put_status(:unauthorized) |> json(%{detail: "Refresh token revoked"})
  end

  def call(conn, {:error, :reused}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{detail: "Refresh token already used (possible theft) -- all sessions revoked"})
  end

  def call(conn, {:error, :invalid_or_expired_token}) do
    conn |> put_status(:unprocessable_entity) |> json(%{detail: "Invalid or expired token"})
  end

  def call(conn, {:error, :not_found}) do
    conn |> put_status(:not_found) |> json(%{detail: "Game not found"})
  end

  def call(conn, {:error, :illegal_move}) do
    conn |> put_status(:unprocessable_entity) |> json(%{detail: "Illegal move", code: "illegal_move"})
  end

  def call(conn, {:error, :game_over}) do
    conn |> put_status(:unprocessable_entity) |> json(%{detail: "Game is already over", code: "game_over"})
  end

  def call(conn, {:error, :hint_refused_calibration}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      detail: "Hints aren't available during a \"rate my play\" calibration game",
      code: "hint_refused_calibration"
    })
  end

  def call(conn, {:error, :rate_limited}) do
    conn
    |> put_status(:too_many_requests)
    |> json(%{detail: "Too many voice sessions started recently -- try again later", code: "rate_limited"})
  end

  def call(conn, {:error, :session_already_active}) do
    conn
    |> put_status(:conflict)
    |> json(%{detail: "A voice session is already active", code: "session_already_active"})
  end

  def call(conn, {:error, :already_ended}) do
    conn |> put_status(:unprocessable_entity) |> json(%{detail: "Voice session already ended"})
  end

  def call(conn, {:error, {:openai_error, _status, _body}}) do
    conn |> put_status(:bad_gateway) |> json(%{detail: "Voice service is temporarily unavailable"})
  end

  def call(conn, {:error, {:openai_request_failed, _reason}}) do
    conn |> put_status(:bad_gateway) |> json(%{detail: "Voice service is temporarily unavailable"})
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    conn |> put_status(:unprocessable_entity) |> json(%{detail: "Validation failed", errors: errors})
  end
end
