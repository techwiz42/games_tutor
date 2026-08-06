defmodule GamesTutor.Skill do
  @moduledoc """
  "Rate my play" skill calibration: a Gaussian belief `(estimated_rating,
  rating_sigma)` per `(user, game_type)`, updated by each calibration
  game's result via `GamesTutor.Skill.BayesianUpdate`. See
  `docs/PLAN.md`'s "Skill calibration" section -- explicitly framed as an
  approximate v1 heuristic that improves across games, not a precise
  single-game measurement.
  """
  import Ecto.Query

  alias GamesTutor.Repo
  alias GamesTutor.Accounts.User
  alias GamesTutor.Games.Move
  alias GamesTutor.Skill.{Acpl, BayesianUpdate, RatingAnchorTable, SkillProfile, SkillProfileHistory}

  @default_prior_mu 1200.0
  @default_prior_sigma 400.0
  # Narrower than the blind default -- an onboarding self-report is real
  # signal, even if a rough/unverified one.
  @onboarding_prior_sigma 250.0

  @labels [{1000, "Beginner"}, {1400, "Intermediate"}, {1800, "Advanced"}, {2200, "Strong"}]

  def get_profile(user, game_type) do
    Repo.get_by(SkillProfile, user_id: user.id, game_type: game_type)
  end

  def list_profiles(user) do
    Repo.all(from p in SkillProfile, where: p.user_id == ^user.id)
  end

  @doc "Ensures a profile exists, seeding a prior (wide default, or narrower if self-reported) if not."
  def get_or_init_profile(user, game_type, opts \\ []) do
    get_profile(user, game_type) || init_profile(user, game_type, opts)
  end

  defp init_profile(user, game_type, opts) do
    self_reported = Keyword.get(opts, :self_reported_elo)

    {mu, sigma} =
      if self_reported, do: {self_reported * 1.0, @onboarding_prior_sigma}, else: {@default_prior_mu, @default_prior_sigma}

    {:ok, profile} =
      %SkillProfile{}
      |> SkillProfile.create_changeset(%{
        user_id: user.id,
        game_type: game_type,
        estimated_rating: mu,
        rating_sigma: sigma,
        display_label: display_label(mu)
      })
      |> Repo.insert()

    profile
  end

  @doc """
  Updates the user's skill profile for `game.game_type` from this
  (already-finished, is_calibration) game's human moves.

  Returns `{:ok, profile}` when updated, or `{:ok, nil}` if the game had
  no analyzable human moves at all (e.g. resigned before move 1) -- not an
  error, just nothing to learn from.
  """
  def record_calibration_result(game) do
    moves = Repo.all(from(m in Move, where: m.game_id == ^game.id, order_by: m.ply))

    case Acpl.compute(moves) do
      {:error, :no_countable_moves} ->
        {:ok, nil}

      {:ok, %{acpl: acpl, moves_counted: n, losses: losses}} ->
        user = Repo.get!(User, game.user_id)
        profile = get_or_init_profile(user, game.game_type)

        observed = RatingAnchorTable.acpl_to_elo(acpl)
        sigma_obs = BayesianUpdate.sigma_obs(losses)

        %{mu: mu_after, sigma: sigma_after} =
          BayesianUpdate.update(profile.estimated_rating, profile.rating_sigma, observed, sigma_obs)

        Repo.transaction(fn ->
          updated =
            profile
            |> SkillProfile.update_changeset(%{
              estimated_rating: mu_after,
              rating_sigma: sigma_after,
              display_label: display_label(mu_after),
              games_count: profile.games_count + 1,
              last_played_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })
            |> Repo.update!()

          %SkillProfileHistory{}
          |> SkillProfileHistory.create_changeset(%{
            skill_profile_id: profile.id,
            game_id: game.id,
            mu_before: profile.estimated_rating,
            sigma_before: profile.rating_sigma,
            acpl: acpl,
            moves_counted: n,
            observed_rating: observed,
            sigma_obs: sigma_obs,
            mu_after: mu_after,
            sigma_after: sigma_after
          })
          |> Repo.insert!()

          updated
        end)
    end
  end

  defp display_label(rating) do
    Enum.find_value(@labels, "Expert", fn {ceiling, label} -> if rating < ceiling, do: label end)
  end
end
