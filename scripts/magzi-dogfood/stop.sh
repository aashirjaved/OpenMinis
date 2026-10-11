#!/bin/bash
# stop the local dogfood magzid (all matching pids) and wait
for p in $(pgrep -f "magzid --config"); do kill $p 2>/dev/null; done
for i in $(seq 1 20); do pgrep -f "magzid --config" >/dev/null || exit 0; sleep 1; done
for p in $(pgrep -f "magzid --config"); do kill -9 $p 2>/dev/null; done
