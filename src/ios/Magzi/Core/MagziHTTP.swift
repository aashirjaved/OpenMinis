import Foundation
import Security

// MARK: - Errors

enum MagziError: LocalizedError, Equatable {
    case notConfigured
    case badURL
    case unauthorized
    case http(Int, String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Magzi isn't connected. Sign in first."
        case .badURL: return "The Magzi server URL is invalid."
        case .unauthorized: return "Your Magzi session expired. Sign in again."
        case .http(_, let message): return message
        case .decoding(let detail): return "Unexpected response from Magzi (\(detail))."
        case .transport(let message): return message
        }
    }

    var statusCode: Int? {
        switch self {
        case .unauthorized: return 401
        case .http(let code, _): return code
        default: return nil
        }
    }
}

// MARK: - JSONValue

/// Raw JSON for shapes that are unknown or free-form (cockpit config, event payloads).
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// Bridges a `JSONSerialization`-style value (`[String: Any]`, `[Any]`, `NSNumber`, …).
    init(any value: Any?) {
        switch value {
        case nil, is NSNull: self = .null
        case let v as JSONValue: self = v
        case let v as String: self = .string(v)
        case let v as NSNumber:
            self = CFGetTypeID(v) == CFBooleanGetTypeID() ? .bool(v.boolValue) : .number(v.doubleValue)
        case let v as [Any]: self = .array(v.map { JSONValue(any: $0) })
        case let v as [String: Any]: self = .object(v.mapValues { JSONValue(any: $0) })
        default: self = .string(String(describing: value!))
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    subscript(index: Int) -> JSONValue? {
        if case .array(let a) = self, a.indices.contains(index) { return a[index] }
        return nil
    }

    var isNull: Bool { self == .null }
    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.rounded() == v ? String(Int64(v)) : String(v)
        case .bool(let v): return v ? "true" : "false"
        default: return nil
        }
    }
    var doubleValue: Double? {
        switch self {
        case .number(let v): return v
        case .string(let v): return Double(v)
        default: return nil
        }
    }
    var intValue: Int? { doubleValue.map { Int($0) } }
    var int64Value: Int64? { doubleValue.map { Int64($0) } }
    var boolValue: Bool? {
        switch self {
        case .bool(let v): return v
        case .number(let v): return v != 0
        case .string(let v): return ["true", "1", "yes", "on"].contains(v.lowercased())
        default: return nil
        }
    }
    var arrayValue: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }

    /// Foundation representation, usable with `JSONSerialization` or `[String: Any]` bodies.
    var anyValue: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .number(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map(\.anyValue)
        case .object(let v): return v.mapValues(\.anyValue)
        }
    }

    /// Re-decodes this value into a typed model.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try MagziHTTP.decoder.decode(T.self, from: JSONEncoder().encode(self))
    }

    /// Parses a JSON-encoded string (e.g. `HouseholdEvent.payload`).
    static func parse(_ string: String?) -> JSONValue? {
        guard let data = string?.data(using: .utf8), !data.isEmpty else { return nil }
        return try? MagziHTTP.decoder.decode(JSONValue.self, from: data)
    }

    var prettyString: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: anyValue, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        ) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - HTTP

/// Body-less success responses (`{ ok: true }` or empty).
struct MagziEmpty: Codable, Hashable, Sendable {}

/// Small JSON-over-HTTP helper shared by the mobile and cockpit clients.
struct MagziHTTP: Sendable {
    let baseURL: URL
    let token: String?
    /// Called (on the main actor) after a 401 on an authenticated request.
    var onUnauthorized: (@MainActor @Sendable () -> Void)?
    var session: URLSession = MagziHTTP.urlSession

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return d
    }()

    static let encoder = JSONEncoder()

    /// Percent-encodes one path segment (household JIDs, conversation ids).
    static func segment(_ raw: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~!$&'()*+,;=:@")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }

    /// Normalises user input like `100.1.2.3:8767` into a URL without a trailing slash.
    static func normalizeBaseURL(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    // MARK: Verbs

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await send("GET", path, query: query, body: nil)
    }

    func post<T: Decodable>(_ path: String, body: (any Encodable)? = nil, headers: [String: String] = [:]) async throws -> T {
        try await send("POST", path, body: try Self.encode(body), headers: headers)
    }

    func post<T: Decodable>(_ path: String, json: [String: Any], headers: [String: String] = [:]) async throws -> T {
        try await send("POST", path, body: try Self.encode(json: json), headers: headers)
    }

    func put<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        try await send("PUT", path, body: try Self.encode(body))
    }

    func put<T: Decodable>(_ path: String, json: [String: Any]) async throws -> T {
        try await send("PUT", path, body: try Self.encode(json: json))
    }

    func patch<T: Decodable>(_ path: String, body: (any Encodable)? = nil) async throws -> T {
        try await send("PATCH", path, body: try Self.encode(body))
    }

    func patch<T: Decodable>(_ path: String, json: [String: Any]) async throws -> T {
        try await send("PATCH", path, body: try Self.encode(json: json))
    }

    func delete<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        try await send("DELETE", path, query: query, body: nil)
    }

    /// Raw bytes (e.g. the weekly PDF).
    func data(_ path: String, method: String = "GET", query: [String: String?] = [:]) async throws -> (Data, HTTPURLResponse) {
        try await perform(try request(method, path, query: query, body: nil, headers: [:]))
    }

    // MARK: Core

    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [String: String?] = [:],
        body: Data?,
        headers: [String: String] = [:]
    ) async throws -> T {
        let (data, _) = try await perform(try request(method, path, query: query, body: body, headers: headers))
        let payload = data.isEmpty ? Data("{}".utf8) : data
        do {
            return try Self.decoder.decode(T.self, from: payload)
        } catch let error as DecodingError {
            throw MagziError.decoding(Self.describe(error))
        }
    }

    func request(_ method: String, _ path: String, query: [String: String?], body: Data?, headers: [String: String]) throws -> URLRequest {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + (path.hasPrefix("/") ? path : "/" + path)) else {
            throw MagziError.badURL
        }
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        guard let url = components.url else { throw MagziError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if method != "GET" && method != "DELETE" {
            // axum's Json extractor rejects body-less POSTs on some routes; an empty object is always safe.
            req.httpBody = Data("{}".utf8)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return req
    }

    private func perform(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            // A cancelled task (e.g. `.task(id:)` restarting) is not a network failure.
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw MagziError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw MagziError.transport("No HTTP response") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                if token != nil, let onUnauthorized { await onUnauthorized() }
                throw MagziError.unauthorized
            }
            throw MagziError.http(http.statusCode, Self.errorMessage(data, status: http.statusCode))
        }
        return (data, http)
    }

    // MARK: Helpers

    static func errorMessage(_ data: Data, status: Int) -> String {
        struct Body: Decodable { let error: String? }
        if let body = try? decoder.decode(Body.self, from: data), let message = body.error, !message.isEmpty {
            return message
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status).capitalized : String(text.prefix(300))
    }

    static func encode(_ body: (any Encodable)?) throws -> Data? {
        guard let body else { return nil }
        return try encoder.encode(body)
    }

    static func encode(json: [String: Any]) throws -> Data {
        // Round-trip through JSONValue so nested JSONValue / Encodable-free values serialise cleanly.
        try JSONSerialization.data(withJSONObject: JSONValue(any: json).anyValue)
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let ctx): return "missing \(path(ctx.codingPath + [key]))"
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx): return "bad value at \(path(ctx.codingPath))"
        case .dataCorrupted(let ctx): return ctx.codingPath.isEmpty ? "invalid JSON" : "corrupt \(path(ctx.codingPath))"
        @unknown default: return "decode error"
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
}

// MARK: - Keychain

enum MagziKeychain {
    static func get(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, service: String, account: String) -> Bool {
        delete(service: service, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func delete(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

extension Int64 {
    /// Converts Magzi epoch milliseconds to a `Date`.
    var magziDate: Date { Date(timeIntervalSince1970: TimeInterval(self) / 1000) }
}

extension Date {
    var magziMs: Int64 { Int64((timeIntervalSince1970 * 1000).rounded()) }
}
