"""Mutating-flow sweep as each member. Prints every call's status; bodies for non-2xx."""
import json, sys, time, uuid, urllib.request, urllib.parse

BASE = "http://127.0.0.1:8767/mobile/v1"
HID_RAW = "javed-home@g.us"
HID = urllib.parse.quote(HID_RAW)


def call(tok, method, path, body=None, hdr=None):
    h = {"Authorization": f"Bearer tok-{tok}", "Content-Type": "application/json"}
    h.update(hdr or {})
    req = urllib.request.Request(BASE + path, method=method, headers=h, data=json.dumps(body).encode() if body is not None else None)
    try:
        r = urllib.request.urlopen(req, timeout=60)
        raw = r.read()
        try: b = json.loads(raw)
        except Exception: b = raw.decode()[:200]
        return r.status, b
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]
    except Exception as e:
        return 0, str(e)


def show(tok, method, path, body=None, hdr=None, expect=(200, 201, 202)):
    st, b = call(tok, method, path, body, hdr)
    flag = "  " if st in expect else "!!"
    extra = "" if st in expect else f" -> {b if isinstance(b, str) else json.dumps(b)[:240]}"
    print(f"{flag} {tok:6} {st} {method} {path} {json.dumps(body) if body else ''}{extra}")
    return st, b


def item_id(b):
    return (b.get("item") or {}).get("id") if isinstance(b, dict) else None


for who in sys.argv[1:] or ["aashir", "sara", "zain", "aliya"]:
    print(f"==== {who}")
    st, b = show(who, "POST", f"/households/{HID}/items", {"title": f"Buy milk ({who})", "kind": "shopping"}, {"Idempotency-Key": str(uuid.uuid4())})
    iid = item_id(b)
    st, b = show(who, "POST", f"/households/{HID}/items", {"title": f"Hoover the stairs ({who})"})
    tid = item_id(b)
    if iid:
        show(who, "PATCH", f"/items/{iid}", {"householdId": HID_RAW, "action": "claim"})
        show(who, "PATCH", f"/items/{iid}", {"householdId": HID_RAW, "action": "done"})
        show(who, "POST", f"/items/{iid}/reopen", {"householdId": HID_RAW})
        show(who, "POST", f"/items/{iid}/progress", {"householdId": HID_RAW, "action": "park"})
        show(who, "POST", f"/items/{iid}/progress", {"householdId": HID_RAW, "action": "reopen"})
        show(who, "POST", f"/items/{iid}/progress", {"householdId": HID_RAW, "action": "schedule", "when": "sat 10:00"})
        show(who, "POST", f"/items/{iid}/progress", {"householdId": HID_RAW, "action": "delegate", "to": "Sara"})
        show(who, "PATCH", f"/items/{iid}", {"householdId": HID_RAW, "action": "drop"})
    if tid:
        show(who, "POST", f"/items/{tid}/swap", {"householdId": HID_RAW, "to": "Zain"})
        show(who, "POST", f"/items/{tid}/skip", {"householdId": HID_RAW})
        show(who, "PATCH", f"/items/{tid}", {"householdId": HID_RAW, "action": "drop"})
    # act on someone else's open item
    st, items = call(who, "GET", f"/households/{HID}/items")
    others = [i for i in (items.get("items", []) if isinstance(items, dict) else []) if i.get("owner") and i["owner"].lower() != who]
    if others:
        o = others[0]
        show(who, "PATCH", f"/items/{o['id']}", {"householdId": HID_RAW, "action": "done"})
        show(who, "POST", f"/items/{o['id']}/reopen", {"householdId": HID_RAW})
    show(who, "POST", f"/households/{HID}/facts", {"label": f"Wifi ({who})", "value": "guest-net"})
    show(who, "POST", f"/households/{HID}/thread", {"text": f"hello from {who} via app", "clientMessageId": str(uuid.uuid4())})
    show(who, "PATCH", "/me/preferences", {"pokeStyle": "gentle"})
    show(who, "PATCH", "/me/preferences", {"brief": "08:00"})
    show(who, "PATCH", "/me/preferences", {"quietHours": "22:00-07:00", "channel": "app"})
    show(who, "POST", "/me/context/presence/heartbeat", {"state": "home"})
    st, sh = call(who, "GET", "/me/context/sharing")
    if isinstance(sh, dict) and "sharing" in sh:
        s = sh["sharing"]; s["presenceVisibleTo"] = "household"
        show(who, "PUT", "/me/context/sharing", s)
    show(who, "POST", "/me/context/visits", {"visits": [{"clientId": str(uuid.uuid4()), "lat": 51.5, "lng": -0.12, "arrivedAt": int(time.time()*1000) - 3600000, "departedAt": int(time.time()*1000)}]})
    show(who, "POST", "/me/context/activities", {"activities": [{"clientId": str(uuid.uuid4()), "kind": "walking", "at": int(time.time()*1000)}]})
    st, mem = call(who, "GET", "/me/memory")
    notes = mem.get("notes", []) if isinstance(mem, dict) else []
    if notes:
        show(who, "PATCH", f"/me/memory/{notes[0]['id']}", {"text": notes[0]["text"]})
    st, ap = call(who, "GET", f"/households/{HID}/approvals")
    pend = [a for a in (ap.get("approvals", []) if isinstance(ap, dict) else []) if a.get("status") == "pending"]
    print(f"   pending approvals: {len(pend)}")
    if pend:
        show(who, "POST", f"/approvals/{pend[0]['id']}/approve")
    show(who, "POST", f"/households/{HID}/invites", {"name": f"Guest {who}", "role": "guest", "email": f"guest-{who}@family.test"})
    show(who, "POST", "/invites/accept", {"code": "nope"}, expect=(400,))
    show(who, "POST", "/me/devices", {"token": "deadbeef", "platform": "ios"})
