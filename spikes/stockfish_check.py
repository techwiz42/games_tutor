"""
Phase 0 spike: confirm Stockfish's actual skill-limiting behavior and Elo floor.

Run:
    spikes/.venv/bin/python3 spikes/stockfish_check.py
"""
import time
import chess
import chess.engine

STOCKFISH_PATH = "spikes/engines/bin/stockfish"


def print_uci_options(engine):
    print("=== Relevant UCI options (name: min-max, default) ===")
    for name in ("UCI_LimitStrength", "UCI_Elo", "Skill Level"):
        opt = engine.options.get(name)
        if opt is None:
            print(f"{name}: NOT FOUND")
            continue
        print(f"{name}: type={opt.type} default={opt.default} min={opt.min} max={opt.max}")
    print()


def test_elo_floor(engine):
    print("=== UCI_LimitStrength + UCI_Elo behavior ===")
    board = chess.Board()
    for target_elo in (500, 800, 1000, 1320, 1350, 1500, 2000):
        try:
            engine.configure({"UCI_LimitStrength": True, "UCI_Elo": target_elo})
            start = time.time()
            result = engine.play(board, chess.engine.Limit(time=0.5))
            elapsed = time.time() - start
            print(f"  target_elo={target_elo}: accepted, move={result.move}, think_time={elapsed:.2f}s")
        except Exception as e:
            print(f"  target_elo={target_elo}: REJECTED -- {e}")
    print()


def test_skill_level(engine):
    print("=== Skill Level (0-20) behavior, UCI_LimitStrength off ===")
    board = chess.Board()
    engine.configure({"UCI_LimitStrength": False})
    for level in (0, 5, 10, 15, 20):
        engine.configure({"Skill Level": level})
        start = time.time()
        result = engine.play(board, chess.engine.Limit(time=0.5))
        elapsed = time.time() - start
        print(f"  skill_level={level}: move={result.move}, think_time={elapsed:.2f}s")
    print()


def test_analysis_vs_opponent_engine_independence(engine_analysis, engine_opponent):
    print("=== Confirm two independently-configured engine instances don't interfere ===")
    engine_opponent.configure({"UCI_LimitStrength": False, "Skill Level": 0})
    engine_analysis.configure({"UCI_LimitStrength": False, "Skill Level": 20})

    board = chess.Board()
    board.push_san("e4")
    board.push_san("e5")

    opp_result = engine_opponent.play(board, chess.engine.Limit(time=0.3))
    info = engine_analysis.analyse(board, chess.engine.Limit(depth=16))
    print(f"  weak opponent engine move suggestion: {opp_result.move}")
    print(f"  full-strength analysis eval (depth 16): {info['score']}")
    print()


if __name__ == "__main__":
    with chess.engine.SimpleEngine.popen_uci(STOCKFISH_PATH) as engine:
        print(f"Engine: {engine.id}\n")
        print_uci_options(engine)
        test_elo_floor(engine)
        test_skill_level(engine)

    with chess.engine.SimpleEngine.popen_uci(STOCKFISH_PATH) as e1, \
         chess.engine.SimpleEngine.popen_uci(STOCKFISH_PATH) as e2:
        test_analysis_vs_opponent_engine_independence(e1, e2)

    print("Spike complete.")
