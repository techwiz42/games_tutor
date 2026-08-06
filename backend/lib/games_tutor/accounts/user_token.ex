defmodule GamesTutor.Accounts.UserToken do
  @moduledoc """
  Unified token table for refresh tokens ("refresh"), email confirmation
  ("confirm"), and password reset ("reset_password"). Every token is stored
  hashed (SHA-256) -- the raw value is only ever returned to the caller once,
  at issuance, and appears in a URL/header, never persisted in plaintext.

  Refresh tokens are additionally rotated on every use: `replaced_by_token_id`
  chains old -> new, so reuse of an already-rotated token is a detectable
  theft signal, not just "invalid". This mirrors the security model built for
  the (now-replaced) Python/FastAPI backend -- same guarantees, reimplemented.
  """
  use Ecto.Schema
  import Ecto.Query

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_tokens" do
    field :token_hash, :string
    field :context, :string
    field :sent_to, :string
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    field :replaced_by_token_id, :binary_id

    belongs_to :user, GamesTutor.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @refresh_ttl_days 30
  @confirm_ttl_hours 24
  @reset_ttl_hours 2

  def build(user, context, opts \\ []) do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    hashed_token = hash(raw_token)

    ttl =
      case context do
        "refresh" -> {@refresh_ttl_days, :day}
        "confirm" -> {@confirm_ttl_hours, :hour}
        "reset_password" -> {@reset_ttl_hours, :hour}
      end

    expires_at =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> add_ttl(ttl)

    token = %__MODULE__{
      user_id: user.id,
      token_hash: hashed_token,
      context: context,
      sent_to: Keyword.get(opts, :sent_to),
      expires_at: expires_at
    }

    {raw_token, token}
  end

  def hash(raw_token) do
    :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
  end

  defp add_ttl(datetime, {amount, :day}), do: DateTime.add(datetime, amount * 86_400, :second)
  defp add_ttl(datetime, {amount, :hour}), do: DateTime.add(datetime, amount * 3_600, :second)

  def by_hash_and_context_query(raw_token, context) do
    hashed = hash(raw_token)
    from t in __MODULE__, where: t.token_hash == ^hashed and t.context == ^context
  end

  def active_chain_query(user_id, context) do
    from t in __MODULE__,
      where: t.user_id == ^user_id and t.context == ^context and is_nil(t.revoked_at)
  end

  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end
end
