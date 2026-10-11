"""Seed a local dogfood household through the real mobile API.

Test-only: sessions are minted straight into the local mobile.db (no SMTP here);
everything else goes through magzid's HTTP routes.
"""
import hashlib, json, sqlite3, sys, time, urllib.request

STATE = sys.argv[1]
BASE = "http://127.0.0.1:8767/mobile/v1"
HID = "javed-home@g.us"
NOW = int(time.time() * 1000)
db = sqlite3.connect(f"{STATE}/mobile.db")


def mint(user_id, token):
    h = hashlib.sha256(f"magzi-mobile-bearer-v1:{token}".encode()).hexdigest()
    db.execute("INSERT OR REPLACE INTO mobile_sessions VALUES(?,?,?,?,?,?,?,?,NULL)",
               (f"ses_{token}", user_id, f"dev-{token}", "Seed", h, NOW, NOW, NOW + 30 * 86400000))
    db.commit()


def call(method, path, token, body=None):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=60))
    except urllib.error.HTTPError as e:
        return {"_status": e.code, "_body": e.read().decode()[:300]}


admin_id = db.execute("SELECT user_id FROM mobile_users WHERE role='admin'").fetchone()[0]
db.execute("UPDATE mobile_users SET display_name='Aashir' WHERE user_id=?", (admin_id,)); db.commit()
mint(admin_id, "tok-aashir")

family = [  # name, email, app role, household role, fake phone
    ("Aashir", None, None, "adult", "+447700900101"),
    ("Sara", "sara@family.test", "family", "adult", "+447700900102"),
    ("Zain", "zain@family.test", "family", "teen", "+447700900103"),
    ("Aliya", "aliya@family.test", "family", "child", "+447700900104"),
]
tokens = {"Aashir": "tok-aashir"}
for name, email, role, hrole, phone in family:
    uid = admin_id
    if email:
        r = call("POST", "/users", "tok-aashir", {"email": email, "displayName": name, "role": role, "scopes": ["chat"]})
        uid = (r.get("user") or {}).get("userId") or db.execute("SELECT user_id FROM mobile_users WHERE email=?", (email,)).fetchone()[0]
        tokens[name] = f"tok-{name.lower()}"
        mint(uid, tokens[name])
    inv = call("POST", f"/households/{urllib.parse.quote(HID)}/invites", "tok-aashir", {"name": name, "role": hrole, "phone": phone})
    code = (inv.get("invite") or inv).get("code")
    acc = call("POST", "/invites/accept", tokens[name], {"code": code})
    print(name, hrole, "invite:", "ok" if code else inv, "| accept:", acc.get("membership", acc).get("state", acc) if isinstance(acc, dict) else acc)

for name, tok in tokens.items():
    hh = call("GET", "/households", tok)
    me = call("GET", "/me", tok)
    print(f"{name:7} households={[h['name'] for h in hh.get('households', [])]} person={(me.get('person') or {}).get('display_name')}")
json.dump(tokens, open(f"{STATE}/../tokens.json", "w"))
