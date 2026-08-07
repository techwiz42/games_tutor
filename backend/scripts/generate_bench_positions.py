#!/usr/bin/env python3
"""
One-off generator for scripts/katago_bench_positions.json (Phase 4's fixed
benchmark set). Plays a handful of real self-play games (every move is
KataGo's own top suggestion against itself -- no hand-crafted positions,
same approach as board_engine_consistency_test.exs) and samples positions
at varying game stages (opening/midgame/endgame) from each. Run once,
directly: `python3 scripts/generate_bench_positions.py`. The output file is
committed and reused by katago_bench.py -- this generator does not need to
run again unless the fixture is deliberately being regenerated.
"""
import json
import subprocess
import sys

KATAGO_BIN = "spikes/engines/bin/katago"
CONFIG = "backend/priv/katago/analysis.cfg"
MODEL = "spikes/engines/models/kata1-b6c96.txt.gz"

GAMES = 4
MOVES_PER_GAME = 40
# Ply offsets sampled from each game (clamped to however long the game
# actually ran, e.g. if it ends in back-to-back passes early).
SAMPLE_PLIES = [4, 12, 24, 36, 44]


def query(proc, history, max_visits):
    req = {
        "id": "q", "moves": history, "rules": "tromp-taylor", "komi": 7.5,
        "boardXSize": 9, "boardYSize": 9, "analyzeTurns": [len(history)],
        "maxVisits": max_visits,
    }
    proc.stdin.write(json.dumps(req) + "\n")
    proc.stdin.flush()
    return json.loads(proc.stdout.readline())


def play_game(proc):
    history = []
    color = "B"
    consecutive_passes = 0
    positions = [list(history)]  # ply 0 (empty board) always included
    for _ in range(MOVES_PER_GAME):
        if consecutive_passes >= 2:
            break
        resp = query(proc, history, 150)
        move_infos = resp.get("moveInfos") or []
        move = move_infos[0]["move"] if move_infos else "pass"
        consecutive_passes = consecutive_passes + 1 if move == "pass" else 0
        history = history + [[color, move]]
        positions.append(list(history))
        color = "W" if color == "B" else "B"
    return positions


def label_for(game_n, ply, total_plies):
    if ply == 0:
        return f"game{game_n} empty board"
    frac = ply / max(total_plies, 1)
    stage = "opening" if frac < 0.3 else "midgame" if frac < 0.7 else "endgame"
    return f"game{game_n} {stage} (ply {ply})"


def main():
    proc = subprocess.Popen(
        [KATAGO_BIN, "analysis", "-config", CONFIG, "-model", MODEL],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1,
    )

    saved = []
    for game_n in range(1, GAMES + 1):
        positions = play_game(proc)
        total_plies = len(positions) - 1
        for offset in SAMPLE_PLIES:
            ply = min(offset, total_plies)
            history = positions[ply]
            saved.append({"label": label_for(game_n, ply, total_plies), "moves": history})

    proc.stdin.close()
    proc.wait(timeout=10)

    # Dedup (short games can make two offsets clamp to the same ply).
    seen = set()
    deduped = []
    for p in saved:
        key = json.dumps(p["moves"])
        if key not in seen:
            seen.add(key)
            deduped.append(p)

    print(f"{len(deduped)} distinct positions", file=sys.stderr)
    with open("backend/scripts/katago_bench_positions.json", "w") as f:
        json.dump(deduped, f, indent=2)


if __name__ == "__main__":
    main()
