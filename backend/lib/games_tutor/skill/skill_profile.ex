defmodule GamesTutor.Skill.SkillProfile do
  @moduledoc """
  A user's running skill estimate for one game type -- a Gaussian belief
  `(estimated_rating, rating_sigma)` updated by each "rate my play"
  (calibration) game's result. See `GamesTutor.Skill.BayesianUpdate`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "skill_profiles" do
    belongs_to :user, GamesTutor.Accounts.User
    field :game_type, :string
    field :estimated_rating, :float
    field :rating_sigma, :float
    field :display_label, :string
    field :games_count, :integer, default: 0
    field :last_played_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def create_changeset(profile, attrs) do
    profile
    |> cast(attrs, [:user_id, :game_type, :estimated_rating, :rating_sigma, :display_label])
    |> validate_required([:user_id, :game_type, :estimated_rating, :rating_sigma])
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:user_id, :game_type])
  end

  def update_changeset(profile, attrs) do
    cast(profile, attrs, [:estimated_rating, :rating_sigma, :display_label, :games_count, :last_played_at])
  end
end
