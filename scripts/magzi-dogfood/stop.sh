#!/bin/bash
# stop the local dogfood magzid (all matching pids) and its WhatsApp stub, and wait
for p in $(pgrep -f "magzid --config"); do kill $p 2>/dev/null; done
for i in $(seq 1 20); do pgrep -f "magzid --config" >/dev/null || break; sleep 1; done
for p in $(pgrep -f "magzid --config"); do kill -9 $p 2>/dev/null; done
# the stub only dies on its next write (EPIPE); don't leave one per restart behind
for p in $(pgrep -f "stub/bridge.js"); do kill $p 2>/dev/null; done
exit 0
