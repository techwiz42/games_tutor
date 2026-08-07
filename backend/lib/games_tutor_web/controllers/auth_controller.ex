defmodule GamesTutorWeb.AuthController do
  use GamesTutorWeb, :controller

  alias GamesTutor.Accounts
  alias GamesTutor.Guardian

  action_fallback GamesTutorWeb.FallbackController

  def register(conn, params) do
    with :ok <- check_ip_rate_limit(conn, "register", 5, 3600),
         {:ok, _user} <- Accounts.register_user(params) do
      conn
      |> put_status(:created)
      |> json(%{message: "Registration successful. Check your email to confirm your account."})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    with :ok <- check_ip_rate_limit(conn, "login", 20, 900) do
      case Accounts.authenticate_user(email, password, client_ip(conn)) do
        {:ok, user} -> render_tokens(conn, user, :ok)
        {:error, :not_confirmed} -> {:error, :not_confirmed}
        {:error, :banned} -> {:error, :banned}
        {:error, :invalid_credentials} -> {:error, :invalid_credentials}
      end
    end
  end

  def login(_conn, _params), do: {:error, :bad_request}

  def refresh(conn, %{"refresh_token" => raw_token}) do
    with {:ok, old_token} <- Accounts.get_valid_refresh_token(raw_token),
         user when not is_nil(user) <- Accounts.get_user(old_token.user_id),
         {:ok, new_raw_refresh} <- Accounts.issue_refresh_token(user, replaces: old_token) do
      conn
      |> put_status(:ok)
      |> json(%{
        access_token: Guardian.issue_access_token(user),
        refresh_token: new_raw_refresh,
        token_type: "bearer"
      })
    else
      nil -> {:error, :invalid_credentials}
      {:error, reason} -> {:error, reason}
    end
  end

  def refresh(_conn, _params), do: {:error, :bad_request}

  def logout(conn, %{"refresh_token" => raw_token}) do
    :ok = Accounts.revoke_refresh_token(raw_token)
    send_resp(conn, :no_content, "")
  end

  def logout(_conn, _params), do: {:error, :bad_request}

  def me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    render_user(conn, user)
  end

  def confirm_email(conn, %{"token" => raw_token}) do
    with {:ok, user} <- Accounts.confirm_user(raw_token) do
      render_tokens(conn, user, :ok)
    end
  end

  def confirm_email(_conn, _params), do: {:error, :bad_request}

  def resend_confirmation(conn, %{"email" => email}) do
    with :ok <- check_ip_rate_limit(conn, "resend_confirmation", 5, 3600) do
      :ok = Accounts.resend_confirmation(email)
      json(conn, %{message: "If that account exists and isn't confirmed, a new confirmation email was sent."})
    end
  end

  def resend_confirmation(_conn, _params), do: {:error, :bad_request}

  def forgot_password(conn, %{"email" => email}) do
    with :ok <- check_ip_rate_limit(conn, "forgot_password", 5, 3600) do
      :ok = Accounts.deliver_password_reset(email)
      json(conn, %{message: "If that email is registered, a password reset link has been sent."})
    end
  end

  def forgot_password(_conn, _params), do: {:error, :bad_request}

  def reset_password(conn, %{"token" => raw_token, "password" => new_password}) do
    case Accounts.reset_password(raw_token, new_password) do
      {:ok, _user} ->
        json(conn, %{message: "Password reset successful. Log in with your new password."})

      {:error, :invalid_or_expired_token} ->
        {:error, :invalid_or_expired_token}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  def reset_password(_conn, _params), do: {:error, :bad_request}

  ## Helpers

  # IP-keyed (not email-keyed): rate-limiting a specific email address
  # would let an attacker deliberately trip a *victim's* own limit and
  # lock them out, a self-inflicted denial-of-service. IP-based bounds
  # automated abuse from a single source without that risk.
  defp check_ip_rate_limit(conn, bucket, max, window_seconds) do
    GamesTutor.RateLimit.check("ratelimit:#{bucket}:#{client_ip(conn)}", max, window_seconds)
  end

  # The frontend proxies /api/* server-to-server (Next.js rewrites -- see
  # frontend/next.config.ts), so conn.remote_ip is always the frontend
  # container's docker IP, not the real client -- every request would
  # otherwise look like it came from the same place. nginx (the actual
  # public-facing edge, see /etc/nginx/sites-available/games.cyberiad.ai) sets
  # X-Forwarded-For correctly; that header survives the Next.js proxy hop
  # since rewrites() forwards incoming headers as-is.
  defp client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [value | _] -> value |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp render_tokens(conn, user, status) do
    {:ok, refresh_token} = Accounts.issue_refresh_token(user, [])

    conn
    |> put_status(status)
    |> json(%{
      access_token: Guardian.issue_access_token(user),
      refresh_token: refresh_token,
      token_type: "bearer"
    })
  end

  defp render_user(conn, user) do
    json(conn, %{
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      created_at: user.inserted_at,
      confirmed: not is_nil(user.confirmed_at),
      has_password: not is_nil(user.hashed_password),
      is_admin: user.is_admin
    })
  end
end
