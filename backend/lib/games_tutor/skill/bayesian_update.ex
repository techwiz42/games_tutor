defmodule GamesTutor.Skill.BayesianUpdate do
  @moduledoc """
  Precision-weighted Gaussian belief update: combines a prior `(mu, sigma)`
  with one game's observation `(obs, sigma_obs)` into a posterior
  `(mu, sigma)`. Standard conjugate-Gaussian update -- precisions
  (1/sigma^2) add, so a confident prior resists a noisy observation and
  vice versa.
  """

  @default_base_sigma_obs 400.0
  @min_sigma_obs 60.0

  @doc "Returns `%{mu: float, sigma: float}`."
  def update(prior_mu, prior_sigma, obs, sigma_obs) do
    prior_precision = 1 / (prior_sigma * prior_sigma)
    obs_precision = 1 / (sigma_obs * sigma_obs)
    total_precision = prior_precision + obs_precision

    mu = (prior_mu * prior_precision + obs * obs_precision) / total_precision
    sigma = :math.sqrt(1 / total_precision)

    %{mu: mu, sigma: sigma}
  end

  @doc """
  Derives this game's observation uncertainty from how much signal it
  actually contains: more moves shrink it (classic 1/sqrt(n) shrinkage of
  a sample-mean's standard error), erratic move-to-move loss (high
  relative to its own mean -- a proxy for inconsistent play) widens it.
  Clamped to a floor so no single game can collapse the belief's
  uncertainty at once; calibration is meant to sharpen gradually across
  games, not converge instantly (see the plan's framing of this as an
  approximate, multi-game heuristic).
  """
  def sigma_obs(losses, opts \\ [])
  def sigma_obs([], opts), do: Keyword.get(opts, :base, @default_base_sigma_obs)

  def sigma_obs(losses, opts) do
    base = Keyword.get(opts, :base, @default_base_sigma_obs)
    n = length(losses)
    mean = Enum.sum(losses) / n

    variance =
      losses
      |> Enum.map(fn l -> (l - mean) * (l - mean) end)
      |> Enum.sum()
      |> Kernel./(n)

    stdev = :math.sqrt(variance)
    erratic_factor = 1 + stdev / (mean + 1)

    (base / :math.sqrt(n) * erratic_factor)
    |> max(@min_sigma_obs)
  end
end
