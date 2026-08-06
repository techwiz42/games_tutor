defmodule GamesTutor.Accounts.User do
  @moduledoc """
  Email is the username -- there is no separate username field. Supports both
  password and Google SSO (either alone is enough: hashed_password and
  google_id are both nullable), matching the prior design.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :hashed_password, :string
    field :password, :string, virtual: true, redact: true
    field :google_id, :string
    field :display_name, :string
    field :avatar_url, :string
    field :confirmed_at, :utc_datetime
    field :last_login_at, :utc_datetime

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

  @doc "Account created/linked via Google OAuth -- no password required."
  def google_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :google_id, :display_name, :avatar_url])
    |> validate_required([:email, :google_id])
    |> validate_email()
    |> unique_constraint(:google_id)
  end

  @doc "Link an existing (password) account to a Google identity."
  def link_google_changeset(user, attrs) do
    user
    |> cast(attrs, [:google_id, :avatar_url])
    |> validate_required([:google_id])
    |> unique_constraint(:google_id)
  end

  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def last_login_changeset(user) do
    change(user, last_login_at: DateTime.utc_now() |> DateTime.truncate(:second))
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
end
