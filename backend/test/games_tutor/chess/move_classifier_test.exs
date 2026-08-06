defmodule GamesTutor.Chess.MoveClassifierTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Chess.MoveClassifier

  test "classifies loss into buckets" do
    assert MoveClassifier.classify(0) == :best
    assert MoveClassifier.classify(10) == :best
    assert MoveClassifier.classify(11) == :good
    assert MoveClassifier.classify(50) == :good
    assert MoveClassifier.classify(51) == :inaccuracy
    assert MoveClassifier.classify(100) == :inaccuracy
    assert MoveClassifier.classify(101) == :mistake
    assert MoveClassifier.classify(300) == :mistake
    assert MoveClassifier.classify(301) == :blunder
    assert MoveClassifier.classify(10_000) == :blunder
  end

  test "clamps negative loss (shouldn't happen upstream, but must not crash/misclassify)" do
    assert MoveClassifier.classify(-50) == :best
  end
end
