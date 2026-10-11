"""Contract-shaped mock of the Magzi mobile API for UI verification in the simulator."""
import http.server, json, time, urllib.parse

NOW = int(time.time() * 1000)
H = 3600_000
HID = "1203630000@g.us"
USER = {"userId": "usr_owner", "email": "owner@example.com", "displayName": "Aashir", "role": "admin",
        "scopes": ["chat", "admin"], "createdBy": "seed", "createdAtMs": NOW - 90 * 24 * H, "disabledAtMs": None}
SESSION = {"sessionId": "ses_1", "userId": "usr_owner", "deviceId": "dev1", "deviceName": "iPhone",
           "createdAtMs": NOW - H, "lastSeenAtMs": NOW, "expiresAtMs": NOW + 30 * 24 * H, "revokedAtMs": None}

def item(i, title, kind="task", owner="Aashir", due=None, status="open", repeat=""):
    return {"id": i, "kind": kind, "title": title, "owner": owner, "status": status, "dueAt": due,
            "dueHasTime": True, "remindAt": None, "reminded": False, "firstStep": "", "estimateMin": 15,
            "energy": "", "notes": "", "createdBy": "Aashir", "createdAt": NOW - 2 * 24 * H, "updatedAt": NOW,
            "doneAt": None, "snoozedUntil": 0, "warnedStage": 0, "area": "home", "repeat": repeat,
            "rotate": False, "private": False, "leadMin": None, "projectId": None}

GROUP = {k: "" for k in ["intensity", "quietHours", "morningAt", "eveningAt", "weeklyReset", "dayKey", "lastMorning",
                         "lastEvening", "lastWeekly", "configHash", "coupleCheckin", "bodyChecks", "lastCouple",
                         "lastBody", "nightBefore", "lastNightBefore", "incidentNote", "lowPowerDay", "tone", "kind",
                         "ownerPersonId", "profileFile", "calendarGrant"]}
GROUP.update({"id": HID, "name": "Javed Home", "enabled": True, "timezone": "Europe/London", "pausedUntil": 0,
              "lastUnsolicitedAt": 0, "lastCaptureAt": NOW, "lastConsideredAt": NOW, "dayCount": 3,
              "lastActivityAt": NOW, "createdAt": NOW - 60 * 24 * H, "incidentUntil": 0, "allclearPending": False})

ITEMS = [item(11, "Book boiler service", due=NOW + 3 * H), item(12, "Renew car insurance", owner="Sara", due=NOW + 26 * H),
         item(13, "Oat milk", kind="shopping", owner=""), item(14, "Bananas", kind="shopping", owner=""),
         item(15, "Pick holiday dates", kind="decision", owner="Sara")]
ACT = [{"action": "schedule", "method": "POST", "path": "/mobile/v1/items/12/progress", "needs": "when"},
       {"action": "drop", "method": "POST", "path": "/mobile/v1/items/12/progress"}]
REALITY = {"week": "2026-W41", "from": NOW - 5 * 24 * H, "to": NOW + 2 * 24 * H,
           "household": {"planned": 18, "done": 12, "confirmed": 9, "likely": 3, "moved": 1, "past": 0, "unknown": 1,
                         "upcoming": 4, "slipping": 1, "parked": 1, "merged": 0},
           "people": [{"name": "Aashir", "planned": 10, "done": 7}, {"name": "Sara", "planned": 8, "done": 5}],
           "fairLoad": {"chores": [["Aashir", 6], ["Sara", 5]], "runs": [["Aashir", 2], ["Sara", 3]]},
           "inferred": [{"itemId": 21, "title": "Bins out", "status": "likely",
                         "evidence": {"kind": "presence", "label": "Was home at 7pm", "strength": "medium",
                                      "reason": "Home during the chore window", "person": "Aashir", "at": NOW - 20 * H},
                         "undo": {"method": "POST", "path": "/mobile/v1/items/21/reopen"}}],
           "slipping": [{"itemId": 12, "title": "Renew car insurance", "owner": "Sara", "days": 3, "actions": ACT}],
           "parked": [{"itemId": 31, "title": "Sort the loft", "actions": ACT}],
           "honesty": {"known": 9, "due": 10, "knownRate": 0.9, "wrong": 1, "inferred": 6, "wrongRate": 0.17, "kinds": []},
           "driver": {"metrics": {"pokes": 7, "acted": 5, "rate": 0.71, "stuck": [], "people": [], "groupToday": 2,
                                  "stage3": 0, "capBreaches": 0, "rescheduled": 1, "rotated": 0, "parked": 1},
                      "items": [{"itemId": 11, "title": "Book boiler service", "owner": "Aashir",
                                 "nextAction": "Call British Gas", "startBy": NOW + 2 * H,
                                 "lead": {"days": 1, "source": "learned", "why": "usually takes a day"},
                                 "stage": 1, "pokes": 1, "noPoke": False}]}}
MESSAGES = [
    {"messageId": "out:3", "conversationId": "mobile:usr_owner", "userId": "usr_owner", "direction": "out",
     "text": "Morning! 3 things today:\n- **Boiler service** call before noon\n- Sara's car insurance renews tomorrow\n- Bins go out tonight",
     "createdAtMs": NOW - 2 * H},
    {"messageId": "in:abc", "conversationId": "mobile:usr_owner", "userId": "usr_owner", "direction": "in",
     "text": "What's for dinner this week?", "createdAtMs": NOW - H},
    {"messageId": "out:4", "conversationId": "mobile:usr_owner", "userId": "usr_owner", "direction": "out",
     "text": "Mon pasta (Sara), Tue tacos (you), Wed leftovers, Thu curry. Want me to add the shopping?",
     "createdAtMs": NOW - H + 30000},
]
ROUTES = {
    "/mobile/v1/bootstrap": {"server": "magzid", "mode": "ProductionActive", "user": USER, "session": SESSION,
                             "features": {"chat": True, "alerts": True, "approvals": True, "push": False}},
    "/mobile/v1/me": {"user": USER, "person": {"person_id": "p_aashir", "display_name": "Aashir"}},
    "/mobile/v1/households": {"households": [GROUP]},
    "/mobile/v1/sessions": {"sessions": [SESSION]},
    "/mobile/v1/conversations/mobile:usr_owner/messages": {"messages": list(reversed(MESSAGES))},
    f"/mobile/v1/households/{HID}/items": {"items": ITEMS},
    f"/mobile/v1/households/{HID}/rota": {"rota": {"people": ["Aashir", "Sara"], "week": [
        {"person": "Aashir", "chores": [{"itemId": 21, "title": "Bins out", "due": NOW + 8 * H}]},
        {"person": "Sara", "chores": [{"itemId": 22, "title": "Hoover downstairs", "due": NOW + 30 * H}]}], "waiting": []}},
    f"/mobile/v1/households/{HID}/bills": {"bills": [{"id": 41, "title": "Council tax", "kind": "bill", "amount": "£182",
                                                      "payer": "Aashir", "due": NOW + 4 * 24 * H, "repeat": "monthly"}],
                                           "renewals": [{"id": 42, "title": "Car insurance", "kind": "renewal", "amount": "£640",
                                                         "payer": "Sara", "due": NOW + 26 * H, "repeat": "yearly"}]},
    f"/mobile/v1/households/{HID}/approvals": {"approvals": [{"id": 51, "householdId": HID, "kind": "send_whatsapp",
        "summary": "Message the plumber to confirm Tuesday", "preview": "Hi Dave, confirming Tue 9am?", "requestedBy": "Magzi",
        "requestedByRole": "agent", "expires": NOW + 6 * H, "status": "pending", "decision": "", "decidedBy": ""}],
        "features": {"approvals": True}},
    f"/mobile/v1/households/{HID}/presence": {"presence": [{"name": "Aashir", "state": "home", "asOf": NOW - 600000},
                                                           {"name": "Sara", "state": "at work", "asOf": NOW - 1200000}]},
    f"/mobile/v1/households/{HID}/reality": REALITY,
    f"/mobile/v1/households/{HID}/meals": {"plan": [{"day": "Monday", "meal": "Pasta", "cook": "Sara", "quick": True},
                                                    {"day": "Tuesday", "meal": "Tacos", "cook": "Aashir", "quick": False}],
                                           "saved": [{"name": "Chicken curry", "ingredients": ["chicken", "rice"], "quick": False}]},
    f"/mobile/v1/households/{HID}/facts": {"facts": [{"key": "wifi", "label": "Wi-Fi", "value": "JavedHome-5G", "updatedAt": NOW}]},
    f"/mobile/v1/households/{HID}/events": {"events": []},
    f"/mobile/v1/households/{HID}/thread": {"lines": [{"id": 2, "speaker": "Magzi", "text": "Bins go out tonight 🗑️", "at": NOW - H,
                                                       "fromMagzi": True, "channel": "whatsapp"},
                                                      {"id": 1, "speaker": "Sara", "text": "I'll do the hoover tomorrow", "at": NOW - 3 * H,
                                                       "fromMagzi": False, "channel": "whatsapp"}]},
    "/mobile/v1/admin/status": {"status": {"startedAt": NOW - 50 * H, "uptimeMs": 50 * H, "whatsappConnectedSince": NOW - 49 * H,
        "whatsappState": "open", "lastInboundAt": NOW - 60000, "lastOutboundAt": NOW - 120000, "llmProvider": "9router/magzi-agent",
        "deadLettersToday": 0, "households": [{"householdId": HID, "name": "Javed Home", "tokensToday": 41200, "budget": 200000}],
        "lastBackupOkAt": NOW - 6 * H, "latency": []}, "text": "Magzi up 2d 2h · WhatsApp open · 9router/magzi-agent"},
}

REC = lambda i, m, st="ok": {"at": NOW - i * 600000, "channel": "whatsapp", "conversationId": "wa:x", "provider": "9router",
                            "model": m, "inputTokens": 3200, "outputTokens": 410, "totalTokens": 3610, "iterations": 2,
                            "status": st, "costTotal": 0.0}
AUDIT = lambda i, scope, action, st="ok": {"time": "2026-10-10T11:%02d:00Z" % i, "session": "wa:x", "run": f"r{i}",
                                           "scope": scope, "action": action, "status": st, "summary": f"{action} via {scope}"}
CAP = lambda t, st, r="low": {"id": t, "toolName": t, "extensionPath": f"ext/{t}", "status": st, "createdAt": "2026-09-01",
                              "validatedAt": None, "sourceUserNeed": "owner asked", "riskLevel": r, "checksum": "x",
                              "sourceChecksum": "x", "validatedChecksum": None, "activatedChecksum": None, "approvedAt": None,
                              "approvedBy": None, "approvalReason": None, "approvalRecordId": None, "activatedAt": None}
COCKPIT = {
    "/api/state": {"agentProfile": "family", "mode": "ProductionActive", "ownerId": "owner", "primaryChannel": "whatsapp",
                   "paused": False,
                   "features": [{"name": "WhatsApp channel", "state": "on", "note": "connected 2d"},
                                {"name": "Telegram channel", "state": "off", "note": ""},
                                {"name": "Long-term memory (knowledge graph)", "state": "attention", "note": "cognee slow"},
                                {"name": "External tools (MCP)", "state": "on", "note": "4 servers"}],
                   "allowlist": ["+44 7700 900123"], "allowlistGrants": {},
                   "whatsappSends": {"lastHour": {"all": 4, "proactive": 1, "ceiling": 30}, "lastDay": {"all": 61, "proactive": 9, "ceiling": 300}},
                   "capabilities": [CAP("trader_scan", "active", "medium"), CAP("studio_publish", "approval_required", "high")],
                   "honesty": [], "config": {"timezone": "Europe/London", "agentProfile": "family", "turnConcurrency": 4}},
    "/api/usage": {"summary": {"turns": 1539, "inputTokens": 4100000, "outputTokens": 520000, "totalTokens": 4620000,
                               "avgContextTokens": 3100, "maxContextTokens": 41000,
                               "byProvider": [["9router", 1500, 4500000], ["chatgpt", 39, 120000]],
                               "byModel": [["9router/magzi-agent", 1400, 4300000], ["9router/magzi-memory", 100, 200000]],
                               "byHousehold": [], "costTotal": 0.0, "recent": [REC(1, "magzi-agent"), REC(2, "magzi-memory", "error")]},
                   "recent": [REC(1, "magzi-agent"), REC(2, "magzi-memory", "error")],
                   "host": {"memTotalMb": 32000, "memUsedMb": 9100, "memAvailableMb": 22900, "memUsedPct": 28.4, "procRssMb": 410,
                            "cpuCores": 8, "load1": 0.6, "load5": 0.5, "load15": 0.4, "cpuLoadPct": 7.5}},
    "/api/sessions": {"sessions": [{"conversation": "wa:family", "lastInput": "bins?", "lastReply": "Tonight, Aashir.", "ts": NOW, "turns": 42}], "count": 1},
    "/api/watch": {"events": [dict(AUDIT(1, "tool", "trader_scan"), source="audit"), dict(AUDIT(2, "llm", "turn", "error"), source="audit")], "count": 2},
    "/api/admin-instructions": {"requests": []},
}

class Handler(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)

    def do_GET(self):
        path = urllib.parse.unquote(urllib.parse.urlparse(self.path).path)
        if path.endswith("/ws"):
            return self._send(404, {"error": "no ws in mock"})
        if path in COCKPIT or path == "/api/session":
            if not (self.headers.get("Authorization") or "").startswith("Bearer "): return self._send(401, {"error": "unauthorized"})
            if path == "/api/session":
                return self._send(200, {"conversation": "wa:family", "pages": [{"input": "bins?", "reply": "Tonight, Aashir.", "ts": NOW, "summary": None}],
                                        "events": [AUDIT(1, "tool", "household_calendar_list")], "usage": []})
            return self._send(200, COCKPIT[path])
        if self.headers.get("Authorization") != "Bearer mock-token":
            return self._send(401, {"error": "unauthorized"})
        self._send(200, ROUTES[path]) if path in ROUTES else self._send(200, {})

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if path == "/mobile/v1/messages":
            body = json.loads(raw or b"{}")
            now = int(time.time() * 1000)
            MESSAGES.append({"messageId": "in:" + body.get("clientMessageId", "x"), "conversationId": "mobile:usr_owner",
                             "userId": "usr_owner", "direction": "in", "text": body.get("text", ""), "createdAtMs": now})
            MESSAGES.append({"messageId": f"out:{now}", "conversationId": "mobile:usr_owner", "userId": "usr_owner",
                             "direction": "out", "text": "Done — added oat milk to the shopping list.", "createdAtMs": now + 1})
            ROUTES["/mobile/v1/conversations/mobile:usr_owner/messages"] = {"messages": list(reversed(MESSAGES))}
            return self._send(202, {"accepted": True, "clientMessageId": body.get("clientMessageId"),
                                    "serverMessageId": f"out:{now}", "conversationId": "mobile:usr_owner", "status": "queued"})
        if path == "/api/login": return self._send(200, {"sent": True})
        if path == "/api/verify": return self._send(200, {"token": "c" * 64})
        if path == "/api/pause":
            COCKPIT["/api/state"]["paused"] = json.loads(raw or b"{}").get("on", False)
            return self._send(200, {"paused": COCKPIT["/api/state"]["paused"]})
        if path == "/mobile/v1/login/verify":
            return self._send(200, {"token": "mock-token", "user": USER, "session": SESSION})
        body = json.loads(raw or b"{}") if raw else {}
        parts = path.strip("/").split("/")
        appr = ROUTES[f"/mobile/v1/households/{HID}/approvals"]["approvals"]
        if len(parts) == 5 and parts[2] == "approvals" and parts[4] in ("approve", "deny"):
            a = next((x for x in appr if str(x["id"]) == parts[3]), None)
            if not a: return self._send(404, {"error": "approval not found"})
            appr.remove(a)
            return self._send(200, {"approval": dict(a, status="approved" if parts[4] == "approve" else "denied")})
        if path == f"/mobile/v1/households/{HID}/items" or urllib.parse.unquote(path) == f"/mobile/v1/households/{HID}/items":
            it = item(100 + len(ITEMS), body.get("title", ""), kind=body.get("kind", "task"), owner="")
            ITEMS.append(it); return self._send(201, {"item": it})
        if len(parts) == 4 and parts[2] == "items":
            it = next((x for x in ITEMS if str(x["id"]) == parts[3]), item(int(parts[3]), "Chore"))
            act = body.get("action", "done")
            if act in ("done", "drop") and it in ITEMS: ITEMS.remove(it)
            return self._send(200, {"item": dict(it, status={"done": "done", "drop": "dropped"}.get(act, it["status"]), owner="Aashir" if act == "claim" else it["owner"])})
        if parts[-1] == "thread":
            line = {"id": 99, "speaker": "Aashir", "text": body.get("text", ""), "at": int(time.time() * 1000), "fromMagzi": False, "channel": "app"}
            ROUTES[f"/mobile/v1/households/{HID}/thread"]["lines"].insert(0, line)
            return self._send(202, {"accepted": True, "messageId": "app:" + body.get("clientMessageId", "c1"), "line": "💬 Aashir (app): " + line["text"]})
        self._send(200, {"accepted": True, "ok": True})

    do_PATCH = do_PUT = do_DELETE = do_POST

    def log_message(self, *a):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", 8767), Handler).serve_forever()
