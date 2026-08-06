defmodule GamesTutor.Chess.UciInfoTest do
  use ExUnit.Case, async: true

  alias GamesTutor.Chess.UciInfo

  test "parses a cp score" do
    line = "info depth 10 seldepth 10 multipv 1 score cp 106 upperbound nodes 14951 nps 1245916"
    assert UciInfo.parse_score(line) == {:cp, 106}
  end

  test "parses a negative cp score" do
    line = "info depth 8 score cp -235 nodes 7849"
    assert UciInfo.parse_score(line) == {:cp, -235}
  end

  test "parses a mate score" do
    line = "info depth 12 seldepth 14 multipv 1 score mate 3 nodes 5000"
    assert UciInfo.parse_score(line) == {:mate, 3}
  end

  test "returns nil for lines with no score field" do
    assert UciInfo.parse_score("bestmove e2e4 ponder d7d5") == nil
    assert UciInfo.parse_score("id name Stockfish 16") == nil
  end

  test "converts scores to centipawns" do
    assert UciInfo.to_centipawns({:cp, 42}) == 42
    assert UciInfo.to_centipawns({:mate, 3}) == 10_000
    assert UciInfo.to_centipawns({:mate, -3}) == -10_000
  end

  test "last_score picks the deepest (last) info line, ignoring non-score lines" do
    lines = [
      "info depth 1 score cp 30",
      "info depth 5 score cp 60",
      "info depth 10 score cp 45 upperbound",
      "bestmove e2e4 ponder d7d5"
    ]

    assert UciInfo.last_score(lines) == {:cp, 45}
  end

  test "last_score returns nil for an empty or scoreless list" do
    assert UciInfo.last_score([]) == nil
    assert UciInfo.last_score(["id name Stockfish 16", "uciok"]) == nil
  end
end
