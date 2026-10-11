#!/bin/bash
# Prints a fresh Ops-cockpit login code from the local dogfood daemon (read from the
# WhatsApp stub's outbox): cockpit-code.sh [dogfood-dir]
D=${1:-$HOME/magzi-dogfood}
python3 - "$D" <<'PY'
import json, re, sys, time, urllib.request
d = sys.argv[1]
urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:8766/api/login', method='POST')).read()
for _ in range(10):
    time.sleep(1)
    lines = [l for l in open(f'{d}/stub/outbox.jsonl') if '"type":"send"' in l and 'login code' in l]
    if lines:
        last = json.loads(lines[-1])
        if time.time() * 1000 - last['at'] < 8000:
            print(re.search(r'code: (\d+)', last['text']).group(1)); break
PY
