defmodule GamesTutor.Guardian do
  @moduledoc "Short-lived JWT access tokens. Refresh tokens are handled
  separately by GamesTutor.Accounts (DB-persisted, hashed, rotated) -- Guardian
  here is only ever used for the access-token half."
  use Guardian, otp_app: :games_tutor

  alias GamesTutor.Accounts

  @access_token_ttl {60, :minutes}

  def subject_for_token(%GamesTutor.Accounts.User{id: id}, _claims), do: {:ok, id}
  def subject_for_token(_, _), do: {:error, :invalid_resource}

  def resource_from_claims(%{"sub" => id}) do
    case Accounts.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_), do: {:error, :invalid_claims}

  def issue_access_token(user) do
    {:ok, token, _claims} = encode_and_sign(user, %{}, ttl: @access_token_ttl)
    token
  end
end
