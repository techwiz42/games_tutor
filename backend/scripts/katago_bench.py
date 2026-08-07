#!/usr/bin/env python3
"""
Phase 4 benchmark harness for the KataGo CPU-reduction work. Starts a real
KataGo analysis process against a given config/model, runs every position
in katago_bench_positions.json (20 real positions sampled from real
self-play games -- see generate_bench_positions.py) at production visit
budgets (300-visit full analysis + 20-visit opponent-move pick per
position, matching GamesTutor.Go.GameServer's own @analysis_max_visits /
@default_opponent_max_visits), and reports wall-clock time, peak CPU%, total
CPU-seconds, and peak RSS.

Not wired into `mix test` -- this is a measurement tool, run directly from
the repo root:

    python3 backend/scripts/katago_bench.py <config> <model> [label]

peak CPU% is sampled periodically (every ~50ms) as instantaneous process
CPU utilization (100% == fully using one core), not just averaged over the
whole run -- useful for seeing how many cores a single query actually
saturates, independent of how many queries ran serially.
"""
import json
import os
import subprocess
import sys
import threading
import time

KATAGO_BIN = "spikes/engines/bin/katago"
POSITIONS_FILE = os.path.join(os.path.dirname(__file__), "katago_bench_positions.json")
ANALYSIS_MAX_VISITS = 300
OPPONENT_MAX_VISITS = 20
POLL_INTERVAL_S = 0.05


def load_positions():
    with open(POSITIONS_FILE) as f:
        return json.load(f)


def build_request(id_, history, max_visits, full_analysis):
    req = {
        "id": id_,
        "moves": history,
        "rules": "tromp-taylor",
        "komi": 7.5,
        "boardXSize": 9,
        "boardYSize": 9,
        "analyzeTurns": [len(history)],
        "maxVisits": max_visits,
    }
    if full_analysis:
        req["includeOwnership"] = True
        req["includePolicy"] = True
    return req


def proc_times(pid):
    """(rss_kb, cpu_seconds) snapshot, or None if the process is gone."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            fields = f.read().split()
        utime, stime = int(fields[13]), int(fields[14])
        clk = os.sysconf("SC_CLK_TCK")
        cpu_seconds = (utime + stime) / clk
        with open(f"/proc/{pid}/status") as f:
            rss_kb = next(
                (int(line.split()[1]) for line in f if line.startswith("VmRSS:")), 0
            )
        return rss_kb, cpu_seconds
    except FileNotFoundError:
        return None


class Sampler:
    """Polls /proc on a genuinely fixed wall-clock interval, in a background
    thread, independent of I/O timing -- sampling only when a response
    happens to arrive (as an earlier version of this script did) lets two
    reads land close enough together that a single /proc CPU-time tick
    (1/SC_CLK_TCK resolution) gets divided by a near-zero wall-clock delta,
    producing spurious four-figure "percent" readings. A fixed interval
    avoids that."""

    def __init__(self, pid, interval_s=POLL_INTERVAL_S):
        self.pid = pid
        self.interval_s = interval_s
        self.peak_rss_kb = 0
        self.peak_cpu_percent = 0.0
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self._thread.start()
        return self

    def stop(self):
        self._stop.set()
        self._thread.join(timeout=2)

    def _run(self):
        last = proc_times(self.pid)
        last_time = time.monotonic()
        while not self._stop.is_set():
            time.sleep(self.interval_s)
            now = time.monotonic()
            snapshot = proc_times(self.pid)
            if not snapshot:
                break
            rss_kb, cpu_seconds = snapshot
            if last:
                dt = now - last_time
                if dt >= self.interval_s * 0.5:
                    cpu_percent = (cpu_seconds - last[1]) / dt * 100
                    self.peak_cpu_percent = max(self.peak_cpu_percent, cpu_percent)
            self.peak_rss_kb = max(self.peak_rss_kb, rss_kb)
            last, last_time = snapshot, now


def main():
    config_path, model_path = sys.argv[1], sys.argv[2]
    label = sys.argv[3] if len(sys.argv) > 3 else config_path
    positions = load_positions()

    proc = subprocess.Popen(
        [KATAGO_BIN, "analysis", "-config", config_path, "-model", model_path],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        bufsize=1,
    )

    # Warm-up: model load / thread pool spin-up shouldn't count against the
    # measured positions below.
    proc.stdin.write(json.dumps(build_request("warmup", [], 1, False)) + "\n")
    proc.stdin.flush()
    proc.stdout.readline()

    requests = []
    for i, pos in enumerate(positions):
        requests.append(build_request(f"analysis{i}", pos["moves"], ANALYSIS_MAX_VISITS, True))
        requests.append(build_request(f"opponent{i}", pos["moves"], OPPONENT_MAX_VISITS, False))

    sampler = Sampler(proc.pid).start()

    start = time.monotonic()
    for req in requests:
        proc.stdin.write(json.dumps(req) + "\n")
    proc.stdin.flush()

    got = 0
    while got < len(requests):
        line = proc.stdout.readline()
        if not line:
            break
        got += 1

    elapsed = time.monotonic() - start
    final_snapshot = proc_times(proc.pid)
    total_cpu_seconds = final_snapshot[1] if final_snapshot else None

    sampler.stop()
    proc.stdin.close()
    proc.wait(timeout=10)

    print(
        f"[{label}] positions={len(positions)} queries={len(requests)} "
        f"wall_clock_s={elapsed:.2f} total_cpu_seconds={total_cpu_seconds:.2f} "
        f"peak_cpu_percent={sampler.peak_cpu_percent:.0f} peak_rss_mb={sampler.peak_rss_kb / 1024:.1f}"
    )


if __name__ == "__main__":
    main()
