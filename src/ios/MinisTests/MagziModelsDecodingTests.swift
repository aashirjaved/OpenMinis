import XCTest
@testable import Minis

/// Decodes contract-shaped samples (docs/magzi-api-contract.md) into the Magzi models.
final class MagziModelsDecodingTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try MagziHTTP.decoder.decode(T.self, from: Data(json.utf8))
    }

    private let userJSON = """
    {"userId":"usr_ab12","email":"a@example.com","displayName":"Aashir","role":"admin",
     "scopes":["chat","admin"],"createdBy":"seed","createdAtMs":1760000000000,"disabledAtMs":null}
    """

    func testBootstrap() throws {
        let json = """
        {"server":"magzid","mode":"ProductionActive","user":\(userJSON),
         "session":{"sessionId":"ses_1","userId":"usr_ab12","deviceId":"dev1","deviceName":"iPhone",
                    "createdAtMs":1760000000000,"lastSeenAtMs":1760000001000,"expiresAtMs":1762592000000,"revokedAtMs":null},
         "features":{"chat":true,"alerts":true,"approvals":true,"push":false}}
        """
        let b = try decode(MagziBootstrap.self, json)
        XCTAssertEqual(b.mode, "ProductionActive")
        XCTAssertEqual(b.user.userId, "usr_ab12")
        XCTAssertTrue(b.user.isAdmin)
        XCTAssertNil(b.user.disabledAtMs)
        XCTAssertEqual(b.session?.sessionId, "ses_1")
        XCTAssertEqual(b.features?.push, false)
        XCTAssertEqual(b.user.appConversationId, "mobile:usr_ab12")
    }

    func testMeSnakeCasePerson() throws {
        let me = try decode(MagziMe.self, #"{"user":\#(userJSON),"person":{"person_id":"p_1","display_name":"Aashir"}}"#)
        XCTAssertEqual(me.person?.personId, "p_1")
        XCTAssertEqual(me.person?.conversationId, "person:p_1")
    }

    func testMessageHistory() throws {
        let json = """
        {"messages":[
          {"messageId":"out:abc","conversationId":"mobile:usr_ab12","userId":"usr_ab12","direction":"out","text":"Hi!","createdAtMs":1760000002000},
          {"messageId":"in:6F1C","conversationId":"mobile:usr_ab12","userId":"usr_ab12","direction":"in","text":"Hello","createdAtMs":1760000001000}
        ]}
        """
        let r = try decode(MagziMessagesResponse.self, json)
        let messages = try XCTUnwrap(r.messages)
        XCTAssertEqual(messages.count, 2)
        XCTAssertFalse(messages[0].isFromUser)
        XCTAssertTrue(messages[1].isFromUser)

        let chat = MagziChatMessage(messages[1])
        XCTAssertEqual(chat.role, .user)
        XCTAssertEqual(chat.clientMessageId, "6F1C")
        XCTAssertEqual(chat.createdAt.magziMs, 1760000001000)
    }

    func testReality() throws {
        let json = """
        {"week":"2026-W41","from":1759708800000,"to":1760313600000,
         "household":{"planned":10,"done":6,"confirmed":4,"likely":2,"moved":1,"past":0,"unknown":1,"upcoming":2,"slipping":1,"parked":1,"merged":0},
         "people":[{"name":"Aashir","planned":5,"done":3}],
         "fairLoad":{"chores":[["Aashir",3],["Sam",2]],"runs":[["Sam",1]]},
         "inferred":[{"itemId":42,"title":"Bins","status":"likely",
            "evidence":{"kind":"presence","label":"Home at 7","strength":"medium","reason":"was home","person":"Sam","at":1760000000000},
            "undo":{"method":"POST","path":"/mobile/v1/items/42/reopen"}}],
         "slipping":[{"itemId":7,"title":"Call plumber","owner":"Aashir","days":3,
            "actions":[{"action":"drop","method":"POST","path":"/mobile/v1/items/7/progress"},
                       {"action":"delegate","method":"POST","path":"/mobile/v1/items/7/progress","needs":"to"}]}],
         "parked":[{"itemId":9,"title":"Garage","actions":[]}],
         "honesty":{"known":5,"due":6,"knownRate":0.83,"wrong":1,"inferred":3,"wrongRate":0.33,
                    "kinds":[{"kind":"presence","wrong":1,"total":3,"demoted":false}]},
         "driver":{"metrics":{"pokes":4,"acted":2,"rate":0.5,"stuck":[7],"people":[{"name":"Aashir","today":1,"cap":3,"maxDay":3}],
                              "groupToday":1,"stage3":0,"capBreaches":0,"rescheduled":1,"rotated":0,"parked":1},
                   "items":[{"itemId":7,"title":"Call plumber","owner":"Aashir","nextAction":"call","startBy":1760000000000,
                             "lead":{"days":2,"source":"default","why":"needs a slot"},"stage":-1,"pokes":0,"noPoke":false}]}}
        """
        let r = try decode(MagziReality.self, json)
        XCTAssertEqual(r.week, "2026-W41")
        XCTAssertEqual(r.household?.done, 6)
        XCTAssertEqual(r.fairLoad?.chores?.first, MagziNamedCount(name: "Aashir", count: 3))
        XCTAssertEqual(r.inferred?.first?.undo?.path, "/mobile/v1/items/42/reopen")
        XCTAssertEqual(r.slipping?.first?.actions?.last?.needs, "to")
        XCTAssertEqual(r.driver?.items?.first?.stage, -1)
        XCTAssertEqual(r.honesty?.kinds?.first?.total, 3)
    }

    func testDeltaEnvelope() throws {
        let json = #"{"type":"message.delta","conversationId":"mobile:usr_ab12","payload":{"delta":"Sure — ","round":1,"seq":3},"cursor":0,"timestamp":"2026-10-10T09:00:01.5+00:00"}"#
        let envelope = try decode(MagziEnvelope.self, json)
        XCTAssertEqual(envelope.cursor, 0)
        guard case let .messageDelta(conv, delta, round, seq) = MagziLiveEvent(envelope: envelope) else {
            return XCTFail("expected message.delta")
        }
        XCTAssertEqual(conv, "mobile:usr_ab12")
        XCTAssertEqual(delta, "Sure — ")
        XCTAssertEqual(round, 1)
        XCTAssertEqual(seq, 3)
    }

    func testReadyAndProactiveDone() throws {
        let ready = try decode(MagziEnvelope.self, #"{"type":"connection.ready","userId":"usr_ab12"}"#)
        XCTAssertEqual(MagziLiveEvent(envelope: ready), .ready(userId: "usr_ab12"))

        let done = try decode(MagziEnvelope.self, """
        {"type":"message.done","conversationId":"mobile:usr_ab12","payload":{"messageId":"out:9","text":"Bins tonight","direction":"out",
         "createdAtMs":1760000003000,"proactive":true,"meta":{"source":"neuro_helper","kind":"nudge","householdId":"1203@g.us","proactive":true}},
         "cursor":0,"timestamp":"2026-10-10T09:00:03+00:00"}
        """)
        guard case let .messageDone(_, payload) = MagziLiveEvent(envelope: done) else { return XCTFail("expected message.done") }
        XCTAssertTrue(payload.isProactive)
        XCTAssertEqual(payload.householdId, "1203@g.us")
    }

    func testHouseholdEventPayloadIsDoubleEncoded() throws {
        let json = #"{"cursor":5,"householdId":"1203@g.us","personId":"usr_ab12","kind":"item.changed","payload":"{\"item\":{\"id\":42,\"title\":\"Milk\",\"kind\":\"shopping\",\"status\":\"open\"}}","idempotencyKey":"k","at":1760000000000}"#
        let event = try decode(MagziHouseholdEvent.self, json)
        XCTAssertEqual(event.item?.id, 42)
        XCTAssertEqual(event.item?.title, "Milk")
    }
}
