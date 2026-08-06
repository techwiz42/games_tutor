defmodule GamesTutor.Accounts.Google do
  @moduledoc "Google OAuth 2.0 helpers -- ported from the prior Python
  implementation (backend/auth/google.py), same logic and validation."

  @auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"

  def generate_state_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  def build_authorization_url(state) do
    params = %{
      client_id: client_id(),
      redirect_uri: redirect_uri(),
      response_type: "code",
      scope: "openid email profile",
      state: state,
      access_type: "offline",
      prompt: "select_account"
    }

    "#{@auth_url}?#{URI.encode_query(params)}"
  end

  @doc "Returns {:ok, claims} or {:error, reason}. claims has string keys:
  sub, email, name, picture, email_verified."
  def exchange_code_for_user_info(code) do
    with {:ok, %{status: 200, body: token_body}} <-
           Req.post(@token_url,
             form: [
               code: code,
               client_id: client_id(),
               client_secret: client_secret(),
               redirect_uri: redirect_uri(),
               grant_type: "authorization_code"
             ]
           ),
         id_token when is_binary(id_token) <- token_body["id_token"],
         {:ok, claims} <- decode_id_token(id_token),
         :ok <- validate_claims(claims) do
      {:ok, claims}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, "Google token exchange failed: #{status} #{inspect(body)}"}

      nil ->
        {:error, "No id_token in Google token response"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Decode without signature verification -- we trust it because we just
  # received it directly from Google over HTTPS in a server-to-server
  # exchange using our client_secret. Still validate aud/iss below.
  defp decode_id_token(id_token) do
    case String.split(id_token, ".") do
      [_header, payload, _sig] ->
        case Base.url_decode64(payload, padding: false) do
          {:ok, json} -> Jason.decode(json)
          :error -> {:error, "Malformed id_token"}
        end

      _ ->
        {:error, "Malformed id_token"}
    end
  end

  defp validate_claims(claims) do
    valid_issuers = ["https://accounts.google.com", "accounts.google.com"]

    cond do
      claims["iss"] not in valid_issuers ->
        {:error, "Invalid id_token issuer: #{claims["iss"]}"}

      claims["aud"] != client_id() ->
        {:error, "Invalid id_token audience"}

      is_nil(claims["sub"]) or is_nil(claims["email"]) ->
        {:error, "Missing sub or email in Google id_token"}

      true ->
        :ok
    end
  end

  defp client_id, do: Application.fetch_env!(:games_tutor, :google_client_id)
  defp client_secret, do: Application.fetch_env!(:games_tutor, :google_client_secret)
  # Routed through the frontend's origin (proxied to the backend server-side
  # by Next.js's rewrites -- see frontend/next.config.ts) rather than the
  # backend's own public_base_url directly. Google redirects the user's
  # browser here, and the browser must only ever need to reach whatever port
  # the frontend is on -- see the games_tutor session notes on why calling
  # the backend's port directly from an external browser doesn't work here.
  # Whoever registers this OAuth app's redirect URI in Google Cloud Console
  # must use this exact value.
  defp redirect_uri, do: "#{Application.fetch_env!(:games_tutor, :frontend_base_url)}/api/auth/google/callback"
end
