defmodule GamesTutor.Accounts.UserSettings do
  @moduledoc """
  Per-user preferences. Currently just the voice tutor's explanation depth
  (adjustable live via the `adjust_explanation_depth` voice tool) -- kept
  minimal rather than building out the plan's full `user_settings` shape
  (e.g. `preferred_voice`) before anything actually reads/writes it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @depths ~w(brief detailed)

  @primary_key {:user_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "user_settings" do
    field :default_explanation_depth, :string, default: "detailed"

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:user_id, :default_explanation_depth])
    |> validate_required([:user_id, :default_explanation_depth])
    |> validate_inclusion(:default_explanation_depth, @depths)
    |> foreign_key_constraint(:user_id)
  end

  def depths, do: @depths
end
