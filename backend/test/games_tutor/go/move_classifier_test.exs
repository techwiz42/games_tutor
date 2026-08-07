defmodule GamesTutor.Go.MoveClassifierTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Go.MoveClassifier

  describe "classify/1 (unscaled fallback)" do
    test "matches the base thresholds exactly" do
      assert MoveClassifier.classify(0) == :best
      assert MoveClassifier.classify(50) == :best
      assert MoveClassifier.classify(51) == :good
      assert MoveClassifier.classify(200) == :good
      assert MoveClassifier.classify(201) == :inaccuracy
      assert MoveClassifier.classify(500) == :inaccuracy
      assert MoveClassifier.classify(501) == :mistake
      assert MoveClassifier.classify(1000) == :mistake
      assert MoveClassifier.classify(1001) == :blunder
    end

    test "negative loss (shouldn't happen upstream, but defensively) clamps to :best" do
      assert MoveClassifier.classify(-100) == :best
    end
  end

  describe "classify/2 volatility scaling (finding 3)" do
    test "nil volatility behaves identically to classify/1 (scale_factor 1.0)" do
      for loss <- [0, 50, 51, 200, 201, 500, 501, 1000, 1001, 5000] do
        assert MoveClassifier.classify(loss, nil) == MoveClassifier.classify(loss)
      end
    end

    test "volatility at the reference point (1800cp) behaves identically to the unscaled base thresholds" do
      for loss <- [0, 50, 51, 200, 201, 500, 501, 1000, 1001, 5000] do
        assert MoveClassifier.classify(loss, 1800) == MoveClassifier.classify(loss)
      end
    end

    test "low volatility (settled endgame) tightens thresholds -- a loss that was :best at reference volatility can become :good" do
      # Phase 0 measured endgame scoreStdev ~79cp -- clamped to min_scale
      # (0.5x), so best/good boundary becomes 25cp, not 50cp.
      assert MoveClassifier.classify(50, 79) == :good
      assert MoveClassifier.classify(25, 79) == :best
      assert MoveClassifier.classify(26, 79) == :good
    end

    test "high volatility (wide-open position) loosens thresholds -- a loss that was :good at reference volatility can become :best" do
      # Phase 0 measured midgame/empty scoreStdev ~2500cp at the high end
      # -- clamped to max_scale (2.0x), so best/good boundary becomes
      # 100cp, not 50cp.
      assert MoveClassifier.classify(50, 5000) == :best
      assert MoveClassifier.classify(100, 5000) == :best
      assert MoveClassifier.classify(101, 5000) == :good
    end

    test "scaling is clamped -- extreme volatility doesn't produce an unbounded threshold" do
      # An absurdly low volatility still can't shrink thresholds past
      # min_scale (0.5x): best/good boundary floors at 25cp, not ~0.
      assert MoveClassifier.classify(25, 1) == :best
      assert MoveClassifier.classify(26, 1) == :good

      # An absurdly high volatility still can't grow thresholds past
      # max_scale (2.0x): best/good boundary caps at 100cp, not unbounded.
      assert MoveClassifier.classify(100, 1_000_000) == :best
      assert MoveClassifier.classify(101, 1_000_000) == :good
    end

    test "the five-label output set is unchanged regardless of volatility" do
      for volatility <- [1, 79, 1800, 5000, 1_000_000] do
        labels = for loss <- [0, 100, 300, 700, 1500], do: MoveClassifier.classify(loss, volatility)
        assert Enum.all?(labels, &(&1 in [:best, :good, :inaccuracy, :mistake, :blunder]))
      end
    end
  end
end
