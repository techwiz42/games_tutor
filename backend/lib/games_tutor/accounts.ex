defmodule GamesTutor.Accounts do
  @moduledoc """
  Public API for users, sessions (refresh tokens), email confirmation, and
  password reset. Controllers call into this module; they never touch
  Ecto/Repo directly.
  """

  import Ecto.Query
  alias GamesTutor.Repo
  alias GamesTutor.Accounts.{User, UserToken, UserSettings}
  alias GamesTutor.Mailer

  ## Users

  def get_user(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> Repo.get(User, id)
      :error -> nil
    end
  end

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  def get_user_by_google_id(google_id) do
    Repo.get_by(User, google_id: google_id)
  end

  @doc """
  Registers a user and sends a confirmation email. Does NOT issue tokens --
  the account can't log in until confirmed (see `authenticate_user/2`).
  """
  def register_user(attrs) do
    with {:ok, user} <- %User{} |> User.registration_changeset(attrs) |> Repo.insert() do
      deliver_confirmation_email!(user)
      {:ok, user}
    end
  end

  @doc "Returns {:ok, user} on success, or {:error, reason} where reason is
  :invalid_credentials or :not_confirmed."
  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    cond do
      user && User.valid_password?(user, password) && User.confirmed?(user) ->
        {:ok, record_login(user)}

      user && User.valid_password?(user, password) ->
        {:error, :not_confirmed}

      true ->
        User.valid_password?(nil, password)
        {:error, :invalid_credentials}
    end
  end

  defp record_login(user) do
    {:ok, user} = user |> User.last_login_changeset() |> Repo.update()
    user
  end

  ## Email confirmation

  @doc "Raises on delivery failure -- used right after registration, where the
  caller just typed this exact email and a loud failure (not a false
  'check your email' success) is the honest response. Not enumeration-
  sensitive: registration itself already reveals whether the address was free."
  def deliver_confirmation_email!(user) do
    {raw_token, token} = UserToken.build(user, "confirm", sent_to: user.email)
    Repo.insert!(token)
    GamesTutor.Emails.confirmation_email(user, raw_token) |> Mailer.deliver!()
    :ok
  end

  # Non-raising: used by resend_confirmation/1, which must return the same
  # response whether or not the account exists -- see that function's doc.
  defp deliver_confirmation_email(user) do
    {raw_token, token} = UserToken.build(user, "confirm", sent_to: user.email)
    Repo.insert!(token)

    case GamesTutor.Emails.confirmation_email(user, raw_token) |> Mailer.deliver() do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.error("Confirmation email delivery failed: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Confirms the account for a valid, unexpired "confirm" token and consumes it
  (deletes it -- confirmation tokens are single-use). Returns {:ok, user} or
  {:error, :invalid_or_expired_token}.
  """
  def confirm_user(raw_token) do
    Repo.transaction(fn ->
      with %UserToken{} = token <- Repo.one(UserToken.by_hash_and_context_query(raw_token, "confirm")),
           false <- UserToken.expired?(token),
           %User{} = user <- Repo.get(User, token.user_id) do
        # Single atomic write for both fields -- confirming also auto-issues
        # login tokens (see AuthController.confirm_email), so it's a real
        # login moment too, not just a confirmation.
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        {:ok, user} = user |> Ecto.Changeset.change(confirmed_at: now, last_login_at: now) |> Repo.update()
        Repo.delete!(token)
        user
      else
        _ -> Repo.rollback(:invalid_or_expired_token)
      end
    end)
  end

  @doc "Re-sends a confirmation email. Silently no-ops if already confirmed or
  the email doesn't exist, to avoid leaking account existence/state."
  def resend_confirmation(email) do
    case get_user_by_email(email) do
      %User{confirmed_at: nil} = user -> deliver_confirmation_email(user)
      _ -> :ok
    end

    :ok
  end

  ## Password reset

  @doc "Always returns :ok regardless of whether the email exists -- prevents
  user enumeration via response-timing/content differences."
  def deliver_password_reset(email) do
    case get_user_by_email(email) do
      %User{} = user ->
        {raw_token, token} = UserToken.build(user, "reset_password", sent_to: user.email)
        Repo.insert!(token)

        # This endpoint must always return :ok regardless of send outcome --
        # the response shape is the user-enumeration boundary (see moduledoc),
        # so a real send failure can't be allowed to change it (e.g. by
        # raising into a 500 only when the account exists, which would itself
        # leak existence via status code). Fail loudly via logging instead.
        case GamesTutor.Emails.reset_password_email(user, raw_token) |> Mailer.deliver() do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            require Logger
            Logger.error("Password reset email delivery failed: #{inspect(reason)}")
        end

      nil ->
        :ok
    end

    :ok
  end

  @doc "Returns {:ok, user} or {:error, :invalid_or_expired_token} or
  {:error, changeset}."
  def reset_password(raw_token, new_password) do
    Repo.transaction(fn ->
      with %UserToken{} = token <-
             Repo.one(UserToken.by_hash_and_context_query(raw_token, "reset_password")),
           false <- UserToken.expired?(token),
           %User{} = user <- Repo.get(User, token.user_id) do
        case user |> User.password_changeset(%{password: new_password}) |> Repo.update() do
          {:ok, updated_user} ->
            # Consume this token and any other outstanding reset tokens for the
            # user, and revoke every active refresh token -- a password reset
            # should end every other session, not just satisfy the one link.
            Repo.delete_all(from t in UserToken, where: t.user_id == ^user.id and t.context == "reset_password")
            revoke_all_refresh_tokens(user.id)
            updated_user

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      else
        _ -> Repo.rollback(:invalid_or_expired_token)
      end
    end)
  end

  ## Google OAuth

  @doc """
  Finds or creates a user from verified Google id_token claims. Google-verified
  accounts are auto-confirmed -- Google already verified the email, no need
  for a separate confirmation email. Links to an existing password account
  with the same email if one exists, rather than creating a duplicate.
  """
  def find_or_create_from_google(%{"sub" => sub, "email" => email} = claims) do
    cond do
      user = get_user_by_google_id(sub) ->
        {:ok, record_login(user)}

      user = get_user_by_email(email) ->
        user
        |> User.link_google_changeset(%{google_id: sub, avatar_url: claims["picture"]})
        |> Repo.update()
        |> case do
          {:ok, user} -> {:ok, auto_confirm_if_needed(user) |> record_login()}
          error -> error
        end

      true ->
        %User{}
        |> User.google_changeset(%{
          email: email,
          google_id: sub,
          display_name: claims["name"],
          avatar_url: claims["picture"]
        })
        |> Repo.update()
        |> case do
          {:ok, user} -> {:ok, auto_confirm_if_needed(user) |> record_login()}
          error -> error
        end
    end
  end

  defp auto_confirm_if_needed(%User{confirmed_at: nil} = user) do
    {:ok, user} = user |> User.confirm_changeset() |> Repo.update()
    user
  end

  defp auto_confirm_if_needed(user), do: user

  ## Refresh tokens (sessions)

  def issue_refresh_token(user, replaces: %UserToken{} = old_token) do
    {raw_token, token} = UserToken.build(user, "refresh")

    Repo.transaction(fn ->
      new_row = Repo.insert!(token)

      old_token
      |> Ecto.Changeset.change(
        revoked_at: DateTime.utc_now() |> DateTime.truncate(:second),
        replaced_by_token_id: new_row.id
      )
      |> Repo.update!()

      raw_token
    end)
  end

  def issue_refresh_token(user, []) do
    {raw_token, token} = UserToken.build(user, "refresh")
    Repo.insert!(token)
    {:ok, raw_token}
  end

  @doc """
  Returns {:ok, %UserToken{}} for a valid, unexpired, unrevoked token;
  {:error, :revoked} for an ordinary revoke (e.g. logout); {:error, :reused}
  for reuse of an already-rotated token (revokes the whole chain defensively);
  or {:error, :invalid} / {:error, :expired}.
  """
  def get_valid_refresh_token(raw_token) do
    case Repo.one(UserToken.by_hash_and_context_query(raw_token, "refresh")) do
      nil ->
        {:error, :invalid}

      token ->
        cond do
          UserToken.expired?(token) ->
            {:error, :expired}

          token.revoked_at && token.replaced_by_token_id ->
            revoke_all_refresh_tokens(token.user_id)
            {:error, :reused}

          token.revoked_at ->
            {:error, :revoked}

          true ->
            {:ok, token}
        end
    end
  end

  def revoke_refresh_token(raw_token) do
    case Repo.one(UserToken.by_hash_and_context_query(raw_token, "refresh")) do
      nil ->
        :ok

      %UserToken{revoked_at: nil} = token ->
        token
        |> Ecto.Changeset.change(revoked_at: DateTime.utc_now() |> DateTime.truncate(:second))
        |> Repo.update!()

        :ok

      _ ->
        :ok
    end
  end

  defp revoke_all_refresh_tokens(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.update_all(UserToken.active_chain_query(user_id, "refresh"),
      set: [revoked_at: now]
    )
  end

  ## Settings

  @doc "Returns the user's settings, materializing the row with defaults on first access."
  def get_settings(user) do
    Repo.get(UserSettings, user.id) || init_settings(user)
  end

  defp init_settings(user) do
    {:ok, settings} =
      %UserSettings{} |> UserSettings.changeset(%{user_id: user.id}) |> Repo.insert()

    settings
  end

  @doc "For the adjust_explanation_depth voice tool."
  def update_settings(user, attrs) do
    get_settings(user) |> UserSettings.changeset(attrs) |> Repo.update()
  end
end
