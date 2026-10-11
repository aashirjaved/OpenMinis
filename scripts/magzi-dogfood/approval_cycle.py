"""Teen asks from the app -> adult decides in the app -> teen hears back in the app. Runs approve and deny."""
import json, sys, time, uuid, urllib.request, urllib.parse

B = "http://127.0.0.1:8767/mobile/v1"
HID = urllib.parse.quote("javed-home@g.us")


def call(tok, m, p, b=None):
    r = urllib.request.Request(B + p, method=m, headers={"Authorization": f"Bearer tok-{tok}", "Content-Type": "application/json"},
                               data=json.dumps(b).encode() if b is not None else None)
    try: return json.load(urllib.request.urlopen(r, timeout=60))
    except urllib.error.HTTPError as e: return {"_": e.code, "b": e.read().decode()[:200]}


def chat(member, text, timeout=120):
    tok = member.lower(); uid = call(tok, "GET", "/me")["user"]["userId"]; conv = urllib.parse.quote(f"mobile:{uid}")
    call(tok, "POST", "/messages", {"text": text, "clientMessageId": str(uuid.uuid4())})
    t0 = time.time(); mine = None
    while time.time() - t0 < timeout:
        time.sleep(2)
        msgs = call(tok, "GET", f"/conversations/{conv}/messages?limit=10")["messages"]
        if mine is None:
            mine = next((m["createdAtMs"] for m in msgs if m["direction"] == "in" and m["text"] == text), None); continue
        reply = [m for m in msgs if m["direction"] == "out" and m["createdAtMs"] >= mine]
        if reply: return reply[-1]["text"], reply[-1]["createdAtMs"]
    return None, None


def latest_after(member, after_ms, timeout=90):
    tok = member.lower(); uid = call(tok, "GET", "/me")["user"]["userId"]; conv = urllib.parse.quote(f"mobile:{uid}")
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(3)
        msgs = call(tok, "GET", f"/conversations/{conv}/messages?limit=5")["messages"]
        new = [m for m in msgs if m["direction"] == "out" and m["createdAtMs"] > after_ms]
        if new: return int(time.time() - t0), new[0]["text"]
    return int(time.time() - t0), None


for decision, ask in [("approve", "I can't hoover the stairs tomorrow, can Sara do it?"), ("deny", "can I skip emptying the dishwasher this week?")]:
    print(f"== {decision}: Zain > {ask}")
    reply, at = chat("Zain", ask)
    print("   Magzi:", (reply or "NO REPLY").replace("\n", " / ")[:220])
    pend = [a for a in call("aashir", "GET", f"/households/{HID}/approvals")["approvals"] if a["status"] == "pending"]
    print("   pending:", [(a["id"], a["summary"], a["requestedBy"]) for a in pend])
    if not pend: continue
    r = call("aashir", "POST", f"/approvals/{pend[0]['id']}/{decision}")
    print("   decided:", r.get("approval", r).get("status") if isinstance(r, dict) else r)
    secs, text = latest_after("Zain", at or 0)
    print(f"   Zain hears after {secs}s:", (text or "NOTHING").replace("\n", " / ")[:200])
