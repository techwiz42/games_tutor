defmodule GamesTutor.Skill.BayesianConvergenceTest do
  @moduledoc """
  Phase 6's "multi-game Bayesian convergence validation". `bayesian_update_test.exs`
  covers the single-update math in isolation (Phase 3's bar); this validates the
  property that actually matters end to end -- that repeated calibration games
  pull `estimated_rating` toward a player's real skill and keep it there, across
  a spread of skill levels, not just in one hand-picked case.

  Deterministically seeded (no real engine/ACPL involved -- this is purely about
  the belief-update recurrence, which `GamesTutor.Skill.record_calibration_result/1`
  drives with real per-game observations elsewhere).
  """
  use ExUnit.Case, async: true

  alias GamesTutor.Skill.BayesianUpdate

  @default_prior_mu 1200.0
  @default_prior_sigma 400.0
  # Matches this module's own @min_sigma_obs..typical range for a real
  # multi-move game's derived sigma_obs (see BayesianUpdate.sigma_obs/2).
  @sigma_obs 150.0

  setup do
    :rand.seed(:exsss, {42, 1337, 271_828})
    :ok
  end

  test "a true beginner (rating 800) converges from the default prior within 15 games" do
    assert_converges(800.0)
  end

  test "a true intermediate player (rating 1200, i.e. the prior's own mean) stays put and sharpens" do
    {mu, sigma} = converge(1200.0, 15)
    assert_in_delta mu, 1200.0, 120
    assert sigma < @default_prior_sigma / 2
  end

  test "a true advanced player (rating 1800) converges from the default prior within 15 games" do
    assert_converges(1800.0)
  end

  test "a true master-level player (rating 2400) converges from the default prior within 15 games" do
    assert_converges(2400.0)
  end

  test "sigma shrinks monotonically game over game, regardless of the true rating" do
    {_mu, sigmas} =
      Enum.reduce(1..15, {{@default_prior_mu, @default_prior_sigma}, []}, fn _, {{mu, sigma}, acc} ->
        observed = 1800.0 + :rand.normal() * @sigma_obs
        %{mu: mu, sigma: sigma} = BayesianUpdate.update(mu, sigma, observed, @sigma_obs)
        {{mu, sigma}, [sigma | acc]}
      end)

    sigmas = Enum.reverse(sigmas)
    assert sigmas == Enum.sort(sigmas, :desc)
  end

  test "a player who initially sandbags (plays down) still converges to their real strength given enough games" do
    true_rating = 2200.0
    sandbag_rating = 1000.0

    {mu, sigma} =
      Enum.reduce(1..3, {@default_prior_mu, @default_prior_sigma}, fn _, {mu, sigma} ->
        observed = sandbag_rating + :rand.normal() * @sigma_obs
        %{mu: mu, sigma: sigma} = BayesianUpdate.update(mu, sigma, observed, @sigma_obs)
        {mu, sigma}
      end)

    assert mu < 1200.0, "expected the sandbagged games to pull mu well below the prior, got #{mu}"

    {mu, _sigma} =
      Enum.reduce(1..25, {mu, sigma}, fn _, {mu, sigma} ->
        observed = true_rating + :rand.normal() * @sigma_obs
        %{mu: mu, sigma: sigma} = BayesianUpdate.update(mu, sigma, observed, @sigma_obs)
        {mu, sigma}
      end)

    assert_in_delta mu, true_rating, 200,
      "expected mu (#{mu}) to recover to within 200 of the true rating #{true_rating} after 25 real games"
  end

  defp assert_converges(true_rating) do
    {mu, sigma} = converge(true_rating, 15)

    assert_in_delta mu, true_rating, 120,
      "expected mu (#{mu}) within 120 of true rating #{true_rating} after 15 games"

    assert sigma < @default_prior_sigma / 2,
      "expected sigma (#{sigma}) to have shrunk to less than half the prior sigma (#{@default_prior_sigma}) after 15 games"
  end

  defp converge(true_rating, games) do
    Enum.reduce(1..games, {@default_prior_mu, @default_prior_sigma}, fn _, {mu, sigma} ->
      observed = true_rating + :rand.normal() * @sigma_obs
      %{mu: mu, sigma: sigma} = BayesianUpdate.update(mu, sigma, observed, @sigma_obs)
      {mu, sigma}
    end)
  end
end
