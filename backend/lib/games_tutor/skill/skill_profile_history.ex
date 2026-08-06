defmodule GamesTutor.Skill.SkillProfileHistory do
  @moduledoc """
  Append-only audit trail of each calibration game's contribution to a
  SkillProfile -- one row per calibration game, for progress charts and
  for explaining/debugging why the estimate moved the way it did.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "skill_profile_histories" do
    belongs_to :skill_profile, GamesTutor.Skill.SkillProfile
    belongs_to :game, GamesTutor.Games.Game
    field :mu_before, :float
    field :sigma_before, :float
    field :acpl, :float
    field :moves_counted, :integer
    field :observed_rating, :float
    field :sigma_obs, :float
    field :mu_after, :float
    field :sigma_after, :float

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @fields ~w(skill_profile_id game_id mu_before sigma_before acpl moves_counted observed_rating sigma_obs mu_after sigma_after)a

  def create_changeset(history, attrs) do
    history
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> foreign_key_constraint(:skill_profile_id)
    |> foreign_key_constraint(:game_id)
  end
end
