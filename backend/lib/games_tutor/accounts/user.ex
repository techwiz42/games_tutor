defmodule GamesTutor.Accounts.User do
  @moduledoc """
  Email is the username -- there is no separate username field.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :hashed_password, :string
    field :password, :string, virtual: true, redact: true
    field :display_name, :string
    field :confirmed_at, :utc_datetime
    field :last_login_at, :utc_datetime
    field :last_login_ip, :string
    field :is_admin, :boolean, default: false
    field :banned_at, :utc_datetime
    field :ban_reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Registration with email + password."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :display_name])
    |> validate_required([:email, :password])
    |> validate_email()
    |> validate_password()
    |> put_hashed_password()
  end

  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def last_login_changeset(user, ip \\ nil) do
    change(user, last_login_at: DateTime.utc_now() |> DateTime.truncate(:second), last_login_ip: ip)
  end

  @doc "Bans an account: reason is required -- it's what gets emailed to the user."
  def ban_changeset(user, reason) do
    user
    |> change(banned_at: DateTime.utc_now() |> DateTime.truncate(:second), ban_reason: reason)
    |> validate_required([:ban_reason])
    |> validate_length(:ban_reason, min: 1, max: 2000)
  end

  @doc "Used by both registration and password reset."
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
    |> put_hashed_password()
  end

  defp validate_email(changeset) do
    changeset
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email address")
    |> validate_length(:email, max: 255)
    |> unsafe_validate_unique(:email, GamesTutor.Repo)
    |> unique_constraint(:email)
    |> update_change(:email, &String.downcase/1)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 128)
  end

  defp put_hashed_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end

  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    # Run a hash anyway so login timing doesn't reveal whether the email exists.
    Bcrypt.no_user_verify()
    false
  end

  def confirmed?(%__MODULE__{confirmed_at: nil}), do: false
  def confirmed?(%__MODULE__{}), do: true

  def banned?(%__MODULE__{banned_at: nil}), do: false
  def banned?(%__MODULE__{}), do: true
end
