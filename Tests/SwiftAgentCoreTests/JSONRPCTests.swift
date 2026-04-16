import XCTest
@testable import SwiftAgentCore

/// Wire-level tests for the JSON-RPC 2.0 envelope.
final class JSONRPCTests: XCTestCase {
    private let encoder = JSONEncoder.swiftAgent
    private let decoder = JSONDecoder.swiftAgent

    func testRequestEncodesWithIntegerId() throws {
        let request = JSONRPCRequest(
            id: .int(1),
            method: "tools/list",
            params: nil
        )
        let data = try encoder.encode(request)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"jsonrpc\":\"2.0\""))
        XCTAssertTrue(json.contains("\"id\":1"))
        XCTAssertTrue(json.contains("\"method\":\"tools/list\""))
    }

    func testNotificationHasNilId() throws {
        let notification = JSONRPCRequest(
            id: nil,
            method: "notifications/initialized"
        )
        XCTAssertTrue(notification.isNotification)
        let data = try encoder.encode(notification)
        let roundTrip = try decoder.decode(JSONRPCRequest.self, from: data)
        XCTAssertNil(roundTrip.id)
        XCTAssertTrue(roundTrip.isNotification)
    }

    func testResponseSuccessRoundTrip() throws {
        let response = JSONRPCResponse(
            id: .int(42),
            result: .object(["ok": .bool(true)])
        )
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(JSONRPCResponse.self, from: data)
        XCTAssertEqual(decoded.id, .int(42))
        XCTAssertEqual(decoded.result, .object(["ok": .bool(true)]))
        XCTAssertNil(decoded.error)
    }

    func testResponseErrorRoundTrip() throws {
        let response = JSONRPCResponse(
            id: .int(42),
            error: .methodNotFound("unknown")
        )
        let data = try encoder.encode(response)
        let decoded = try decoder.decode(JSONRPCResponse.self, from: data)
        XCTAssertNil(decoded.result)
        XCTAssertEqual(decoded.error?.code, -32601)
        XCTAssertTrue(decoded.error?.message.contains("unknown") ?? false)
    }

    func testFramingAppendsNewline() throws {
        let request = JSONRPCRequest(id: .int(1), method: "ping")
        let framed = try JSONRPCFraming.encode(request)
        XCTAssertEqual(framed.last, JSONRPCFraming.messageTerminator)
    }

    func testIdAcceptsStringAndInteger() throws {
        let stringIdJSON = #"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#.data(using: .utf8)!
        let intIdJSON = #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#.data(using: .utf8)!

        let stringRequest = try decoder.decode(JSONRPCRequest.self, from: stringIdJSON)
        let intRequest = try decoder.decode(JSONRPCRequest.self, from: intIdJSON)

        XCTAssertEqual(stringRequest.id, .string("abc"))
        XCTAssertEqual(intRequest.id, .int(7))
    }

    func testStandardErrorCodes() {
        XCTAssertEqual(JSONRPCError.parseError().code, -32700)
        XCTAssertEqual(JSONRPCError.invalidRequest().code, -32600)
        XCTAssertEqual(JSONRPCError.methodNotFound("x").code, -32601)
        XCTAssertEqual(JSONRPCError.invalidParams().code, -32602)
        XCTAssertEqual(JSONRPCError.internalError().code, -32603)
    }
}
