import XCTest
@testable import SwiftAgentCore

/// Round-trip and convenience-accessor tests for ``JSONValue``.
///
/// These tests guard the type that every other wire payload flows
/// through — if `JSONValue` round-trips lose fidelity, the whole
/// protocol silently drifts, so the coverage here is deliberately
/// exhaustive across all seven cases.
final class JSONValueTests: XCTestCase {
    private let encoder = JSONEncoder.swiftAgent
    private let decoder = JSONDecoder.swiftAgent

    // MARK: - Round trips

    func testRoundTripPrimitives() throws {
        let samples: [JSONValue] = [
            .null,
            .bool(true),
            .bool(false),
            .int(0),
            .int(Int64.max),
            .int(Int64.min),
            .double(3.14159),
            .string(""),
            .string("hello world")
        ]
        for sample in samples {
            let data = try encoder.encode(sample)
            let decoded = try decoder.decode(JSONValue.self, from: data)
            XCTAssertEqual(decoded, sample, "\(sample) failed to round-trip")
        }
    }

    func testRoundTripArray() throws {
        let value: JSONValue = .array([.int(1), .string("two"), .bool(true), .null])
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testRoundTripObject() throws {
        let value: JSONValue = .object([
            "name": .string("Ada"),
            "age": .int(36),
            "roles": .array([.string("admin"), .string("editor")]),
            "active": .bool(true),
            "nickname": .null
        ])
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, value)
    }

    func testIntegerPreservedAsInteger() throws {
        // Decoding a whole number must produce `.int`, not `.double`.
        let json = "42".data(using: .utf8)!
        let decoded = try decoder.decode(JSONValue.self, from: json)
        XCTAssertEqual(decoded, .int(42))
    }

    func testDoublePreservedAsDouble() throws {
        let json = "42.5".data(using: .utf8)!
        let decoded = try decoder.decode(JSONValue.self, from: json)
        XCTAssertEqual(decoded, .double(42.5))
    }

    // MARK: - Convenience accessors

    func testAccessorsReturnExpectedValues() {
        XCTAssertEqual(JSONValue.bool(true).boolValue, true)
        XCTAssertEqual(JSONValue.int(7).intValue, 7)
        XCTAssertEqual(JSONValue.double(2.0).intValue, 2, "whole double should coerce to int")
        XCTAssertNil(JSONValue.double(2.5).intValue, "non-whole double should not coerce to int")
        XCTAssertEqual(JSONValue.string("x").stringValue, "x")
        XCTAssertEqual(JSONValue.array([.int(1)]).arrayValue, [.int(1)])
        XCTAssertEqual(JSONValue.object(["k": .int(1)]).objectValue, ["k": .int(1)])
        XCTAssertTrue(JSONValue.null.isNull)
    }

    func testObjectSubscriptLookup() {
        let value: JSONValue = .object(["a": .object(["b": .int(42)])])
        XCTAssertEqual(value["a"]?["b"], .int(42))
        XCTAssertNil(value["missing"])
    }

    func testArraySubscriptLookup() {
        let value: JSONValue = .array([.string("zero"), .string("one")])
        XCTAssertEqual(value[0], .string("zero"))
        XCTAssertEqual(value[1], .string("one"))
        XCTAssertNil(value[2])
    }

    // MARK: - Literal construction

    func testLiteralConstruction() {
        let value: JSONValue = [
            "name": "Ada",
            "age": 36,
            "admin": true,
            "notes": nil
        ]
        XCTAssertEqual(value["name"], .string("Ada"))
        XCTAssertEqual(value["age"], .int(36))
        XCTAssertEqual(value["admin"], .bool(true))
        XCTAssertEqual(value["notes"], .null)
    }

    // MARK: - Bridging from Any

    func testInitFromAnyObject() {
        let any: Any = ["x": 1, "y": [true, false]] as [String: Any]
        let value = JSONValue(any: any)
        XCTAssertNotNil(value)
        XCTAssertEqual(value?["x"], .int(1))
        XCTAssertEqual(value?["y"], .array([.bool(true), .bool(false)]))
    }

    func testInitFromAnyRejectsUnknown() {
        struct Unknown {}
        XCTAssertNil(JSONValue(any: Unknown()))
    }
}
