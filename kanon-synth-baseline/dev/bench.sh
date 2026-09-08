#!/bin/zsh
# dev/bench.sh NAME CMD
# Runs CMD once untimed as a warm-up, then RUNS timed runs (RUNS defaults to 5).
# CMD is one string, run as zsh -c CMD, with stdout and stderr sent to /dev/null.
# The timer is perf_counter_ns around subprocess.run, so interpreter start-up is
# outside every measurement.
# Success prints exactly one line:
#   BENCH NAME median_ms=12.345 min_ms=11.000 max_ms=14.200 runs=5
# A non-zero child exit prints BENCH-ERROR NAME exit=N and exits 1.

set -u

if [ $# -ne 2 ]; then
  print -r -- "BENCH-USAGE bench.sh NAME CMD"
  exit 2
fi

BENCH_NAME=$1
BENCH_CMD=$2
BENCH_RUNS=${RUNS:-5}

exec /opt/homebrew/bin/python3 -P - "$BENCH_NAME" "$BENCH_CMD" "$BENCH_RUNS" <<'BENCH_TIMER_EOF'
import os
import statistics
import subprocess
import sys
import time

name = sys.argv[1]
cmd = sys.argv[2]
runs = int(sys.argv[3])


def timed(devnull):
    start = time.perf_counter_ns()
    proc = subprocess.run(
        ["/bin/zsh", "-f", "-c", cmd],
        stdin=devnull,
        stdout=devnull,
        stderr=devnull,
    )
    stop = time.perf_counter_ns()
    return (proc.returncode, (stop - start) / 1000000.0)


def fail(code):
    print("BENCH-ERROR {0} exit={1}".format(name, code))
    sys.exit(1)


def report(samples):
    ms = [ms for (_, ms) in samples]
    print(
        "BENCH {0} median_ms={1:.3f} min_ms={2:.3f} max_ms={3:.3f} runs={4}".format(
            name, statistics.median(ms), min(ms), max(ms), runs
        )
    )
    sys.exit(0)


with open(os.devnull, "r+b") as devnull:
    warm = timed(devnull)
    samples = [warm] if warm[0] != 0 else [timed(devnull) for _ in range(runs)]

bad = next((code for (code, _) in samples if code != 0), None)
report(samples) if bad is None else fail(bad)
BENCH_TIMER_EOF
