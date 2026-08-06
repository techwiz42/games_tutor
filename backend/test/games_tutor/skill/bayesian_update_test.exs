defmodule GamesTutor.Skill.BayesianUpdateTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Skill.BayesianUpdate, as: BU

  describe "update/4" do
    test "a confident prior resists a noisy observation" do
      result = BU.update(1200, 50, 1800, 400)
      # Prior precision >> obs precision, so mu barely moves off 1200.
      assert_in_delta result.mu, 1200, 15
      assert result.sigma < 50
    end

    test "a wide/uncertain prior yields strongly to the observation" do
      result = BU.update(1200, 400, 1800, 60)
      assert_in_delta result.mu, 1800, 60
    end

    test "equal-confidence prior and observation average to the midpoint" do
      result = BU.update(1000, 100, 1400, 100)
      assert_in_delta result.mu, 1200, 0.001
    end

    test "posterior sigma always shrinks relative to both inputs" do
      result = BU.update(1200, 200, 1500, 200)
      assert result.sigma < 200
    end
  end

  describe "sigma_obs/2" do
    test "more moves shrink sigma_obs (more signal -> more confidence)" do
      few = BU.sigma_obs(List.duplicate(50, 3))
      many = BU.sigma_obs(List.duplicate(50, 30))
      assert many < few
    end

    test "erratic (high-variance) play widens sigma_obs vs. consistent play at the same mean" do
      consistent = BU.sigma_obs([50, 50, 50, 50, 50])
      erratic = BU.sigma_obs([5, 5, 5, 5, 230])
      assert erratic > consistent
    end

    test "never drops below the floor even with a huge number of moves" do
      many_consistent = BU.sigma_obs(List.duplicate(10, 200))
      assert many_consistent >= 60.0
    end

    test "empty losses falls back to the base sigma" do
      assert BU.sigma_obs([]) == 400.0
    end
  end
end
