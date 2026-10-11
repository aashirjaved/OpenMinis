"""Contract sweep: every read route the app uses, as each household member. Prints non-2xx only."""
import json, sys, urllib.request, urllib.parse

BASE = "http://127.0.0.1:8767/mobile/v1"
HID = urllib.parse.quote("javed-home@g.us")
MEMBERS = ["aashir", "sara", "zain", "aliya"]


def call(tok, method, path, body=None):
    req = urllib.request.Request(BASE + path, method=method, headers={"Authorization": f"Bearer tok-{tok}", "Content-Type": "application/json"},
                                 data=json.dumps(body).encode() if body is not None else None)
    try:
        r = urllib.request.urlopen(req, timeout=30)
        ct = r.headers.get("content-type", "")
        raw = r.read()
        return r.status, (json.loads(raw) if "json" in ct else f"<{ct} {len(raw)}B>")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:200]
    except Exception as e:
        return 0, str(e)


READS = [
    "/bootstrap", "/me", "/sessions", "/households", "/me/memory", "/me/activity", "/me/time",
    "/me/context/sharing", "/me/places", "/me/timeline",
    f"/households/{HID}/items", f"/households/{HID}/items?view=mine", f"/households/{HID}/items?view=shopping",
    f"/households/{HID}/facts", f"/households/{HID}/rota", f"/households/{HID}/events", f"/households/{HID}/meals",
    f"/households/{HID}/bills", f"/households/{HID}/summary/latest", f"/households/{HID}/thread",
    f"/households/{HID}/reality", f"/households/{HID}/presence", f"/households/{HID}/approvals", f"/households/{HID}/members",
    "/users", "/admin/status", "/admin/qr",
]
only = sys.argv[1:] or MEMBERS
for m in only:
    uid = call(m, "GET", "/me")[1]
    print(f"== {m}: role={uid.get('user',{}).get('role') if isinstance(uid,dict) else uid} person={(uid.get('person') or {}).get('display_name') if isinstance(uid,dict) else ''}")
    conv = f"mobile:{uid['user']['userId']}" if isinstance(uid, dict) else None
    pid = (uid.get("person") or {}).get("person_id") if isinstance(uid, dict) else None
    paths = list(READS)
    if conv: paths.append(f"/conversations/{urllib.parse.quote(conv)}/messages?limit=5")
    if pid: paths.append(f"/conversations/{urllib.parse.quote('person:'+pid)}/messages?limit=5")
    for p in paths:
        st, body = call(m, "GET", p)
        if not (200 <= st < 300):
            print(f"  {st} GET {p} -> {body if isinstance(body,str) else json.dumps(body)[:200]}")
