#!/bin/sh
# Test helper: spawns N background children that sleep, then sleeps itself.
# Usage: spawn_children.sh <n_children> <sleep_time>
# Writes child PIDs to stdout (one per line) before sleeping.
N=${1:-2}
T=${2:-999}

for i in $(seq 1 $N); do
    sleep $T &
    echo $!
done

sleep $T
