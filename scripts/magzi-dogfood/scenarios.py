"""Family chat scenarios through the local magzid (LLM via 9router). Flags apologetic / refusing replies."""
import json, re, sys, time, uuid, urllib.request, urllib.parse

BASE = "http://127.0.0.1:8767/mobile/v1"
BAD = re.compile(r"sorry|can't do|cannot do|couldn't|unable|not possible|didn't work|something went wrong|try again", re.I)

SCENARIOS = [
    ("Aashir", "add dishwasher tablets and bread to the shopping list"),
    ("Aashir", "remind me to call the dentist tomorrow at 9am"),
    ("Aashir", "what bills are due this month?"),
    ("Aashir", "Zain is cooking Wednesday's curry"),
    ("Aashir", "new chore: Zain empties the dishwasher every evening at 7"),
    ("Aashir", "swap my bins chore with Sara this week"),
    ("Sara", "what's for dinner this week?"),
    ("Sara", "I've done the hoovering"),
    ("Sara", "plan dinners for thursday and friday, something quick"),
    ("Sara", "what does Zain have on today?"),
    ("Zain", "I can't do the dishwasher tonight, can Dad do it?"),
    ("Zain", "what's on me tomorrow?"),
    ("Aliya", "I fed the cat"),
    ("Aliya", "can I have ice cream?"),
    ("Aliya", "add sweets to the shopping list please"),
    ("Aashir", "what did everyone get done this week?"),
]


def call(tok, method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, headers={"Authorization": f"Bearer tok-{tok}", "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    return json.load(urllib.request.urlopen(req, timeout=60))


def chat(member, text, timeout=180):
    tok = member.lower()
    uid = call(tok, "GET", "/me")["user"]["userId"]
    conv = urllib.parse.quote(f"mobile:{uid}")
    call(tok, "POST", "/messages", {"text": text, "clientMessageId": str(uuid.uuid4())})
    t0 = time.time(); mine = None
    while time.time() - t0 < timeout:
        time.sleep(2)
        msgs = call(tok, "GET", f"/conversations/{conv}/messages?limit=10")["messages"]
        if mine is None:
            mine = next((m["createdAtMs"] for m in msgs if m["direction"] == "in" and m["text"] == text), None)
            continue
        reply = [m for m in msgs if m["direction"] == "out" and m["createdAtMs"] >= mine]
        if reply:
            return int(time.time() - t0), reply[-1]["text"]
    return int(time.time() - t0), None


only = sys.argv[1:]
for member, text in SCENARIOS:
    if only and member not in only: continue
    secs, reply = chat(member, text)
    flag = "!!" if reply is None or BAD.search(reply or "") else "  "
    print(f"{flag} [{secs:3d}s] {member} > {text}\n      < {(reply or 'NO REPLY').strip()[:600].replace(chr(10), ' / ')}", flush=True)
