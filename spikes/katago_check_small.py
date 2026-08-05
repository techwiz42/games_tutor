"""
Phase 0 spike: measure real KataGo analysis-engine latency on this (CPU-only) machine
at a few visit-count settings, using the JSON stdin/stdout analysis protocol (not GTP) --
this is the mode board-reporting-style tutoring needs (win-rate/score-lead per move).

Run:
    spikes/.venv/bin/python3 spikes/katago_check.py
"""
import json
import subprocess
import time

KATAGO_BIN = "spikes/engines/bin/katago"
CONFIG = "spikes/engines/katago_cfg/spike_analysis.cfg"
MODEL = "spikes/engines/models/kata1-b6c96.txt.gz"

# A short real opening (moves so far), analyze the position after move 4.
QUERY_MOVES = [["B", "Q4"], ["W", "D4"], ["B", "D16"], ["W", "Q16"]]


def run_query(proc, query, timeout_s=60.0):
    start = time.time()
    proc.stdin.write(json.dumps(query) + "\n")
    proc.stdin.flush()
    line = proc.stdout.readline()
    elapsed = time.time() - start
    return json.loads(line), elapsed


if __name__ == "__main__":
    proc = subprocess.Popen(
        [KATAGO_BIN, "analysis", "-config", CONFIG, "-model", MODEL],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, bufsize=1,
    )

    print("Starting KataGo analysis engine (loading network)...")
    load_start = time.time()

    try:
        for visits in (50, 100, 300, 500):
            query = {
                "id": f"spike-{visits}",
                "moves": QUERY_MOVES,
                "rules": "tromp-taylor",
                "komi": 7.5,
                "boardXSize": 19,
                "boardYSize": 19,
                "analyzeTurns": [4],
                "maxVisits": visits,
            }
            result, elapsed = run_query(proc, query)
            if "error" in result:
                print(f"visits={visits}: ERROR -- {result['error']}")
                continue
            first_load_note = ""
            if visits == 50:
                first_load_note = f"  (includes network load time: {elapsed:.2f}s total)"
                load_elapsed = elapsed
            root_info = result.get("rootInfo", {})
            print(
                f"visits={visits}: {elapsed:.3f}s  "
                f"winrate={root_info.get('winrate'):.3f}  "
                f"scoreLead={root_info.get('scoreLead'):.2f}"
                f"{first_load_note}"
            )
    finally:
        proc.stdin.close()
        proc.terminate()
        stderr_tail = proc.stderr.read()[-2000:]
        proc.wait(timeout=10)
        if stderr_tail.strip():
            print("\n--- stderr tail (for diagnosing load time / errors) ---")
            print(stderr_tail)

    print("\nSpike complete.")
