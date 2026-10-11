"""Chat with local magzid as a household member: chat.py <member> <text>"""
import json, sys, time, uuid, urllib.request, urllib.parse

BASE = "http://127.0.0.1:8767/mobile/v1"
tok = f"tok-{sys.argv[1].lower()}"
H = {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}


def call(method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, headers=H,
                                 data=json.dumps(body).encode() if body is not None else None)
    return json.load(urllib.request.urlopen(req, timeout=60))


uid = call("GET", "/me")["user"]["userId"]
conv = f"mobile:{uid}"
sent = call("POST", "/messages", {"text": sys.argv[2], "clientMessageId": str(uuid.uuid4())})
t0 = time.time()
mine = None
while time.time() - t0 < 240:
    time.sleep(3)
    msgs = call("GET", f"/conversations/{urllib.parse.quote(conv)}/messages?limit=10")["messages"]
    if mine is None:
        mine = next((m["createdAtMs"] for m in msgs if m["direction"] == "in" and m["text"] == sys.argv[2]), None)
        continue
    reply = [m for m in msgs if m["direction"] == "out" and m["createdAtMs"] >= mine]
    if reply:
        print(f"[{int(time.time()-t0)}s] {sys.argv[1]} <- Magzi:\n" + reply[0]["text"])
        break
else:
    print("no reply in 240s")
