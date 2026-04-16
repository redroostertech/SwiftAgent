import XCTest
@testable import SwiftAgentCore

/// Tests for the tiny JSON-Schema validator baked into ``MCPSchema``.
final class MCPSchemaTests: XCTestCase {
    func testObjectSchemaValidatesRequiredProperties() {
        let schema = MCPSchema.object(
            properties: [
                "name": .string(),
                "age": .integer(minimum: 0, maximum: 150)
            ],
            required: ["name", "age"]
        )

        let valid: JSONValue = .object([
            "name": .string("Ada"),
            "age": .int(36)
        ])
        XCTAssertEqual(schema.validate(valid), [])
    }

    func testObjectSchemaReportsMissingRequired() {
        let schema = MCPSchema.object(
            properties: [
                "name": .string(),
                "age": .integer()
            ],
            required: ["name", "age"]
        )

        let missing: JSONValue = .object(["name": .string("Ada")])
        let errors = schema.validate(missing)
        XCTAssertFalse(errors.isEmpty)
        XCTAssertTrue(errors.contains { $0.contains("age") && $0.contains("required") })
    }

    func testObjectSchemaRejectsUnknownProperties() {
        let schema = MCPSchema.object(
            properties: ["name": .string()],
            required: ["name"],
            additionalProperties: false
        )
        let extra: JSONValue = .object([
            "name": .string("Ada"),
            "extra": .string("nope")
        ])
        let errors = schema.validate(extra)
        XCTAssertTrue(errors.contains { $0.contains("extra") })
    }

    func testNumericBoundsAreEnforced() {
        let schema = MCPSchema.integer(minimum: 0, maximum: 10)
        XCTAssertEqual(schema.validate(.int(5)), [])
        XCTAssertFalse(schema.validate(.int(-1)).isEmpty)
        XCTAssertFalse(schema.validate(.int(42)).isEmpty)
    }

    func testEnumValidation() {
        let schema = MCPSchema.string(enumValues: ["low", "high"])
        XCTAssertEqual(schema.validate(.string("low")), [])
        XCTAssertEqual(schema.validate(.string("high")), [])
        XCTAssertFalse(schema.validate(.string("medium")).isEmpty)
    }

    func testArraySchemaValidatesElements() {
        let schema = MCPSchema.array(of: .integer(minimum: 0, maximum: 9))
        let valid: JSONValue = .array([.int(1), .int(2), .int(3)])
        XCTAssertEqual(schema.validate(valid), [])

        let invalid: JSONValue = .array([.int(1), .int(42)])
        XCTAssertFalse(schema.validate(invalid).isEmpty)
    }

    func testSchemaRoundTripsThroughCodable() throws {
        let schema = MCPSchema.object(
            properties: [
                "title": .string(description: "Tool title"),
                "count": .integer(minimum: 0)
            ],
            required: ["title"]
        )
        let data = try JSONEncoder.swiftAgent.encode(schema)
        let decoded = try JSONDecoder.swiftAgent.decode(MCPSchema.self, from: data)
        XCTAssertEqual(decoded.type, .object)
        XCTAssertEqual(decoded.required, ["title"])
        XCTAssertEqual(decoded.properties?["title"]?.type, .string)
        XCTAssertEqual(decoded.properties?["count"]?.minimum, 0)
    }
}
