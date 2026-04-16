import XCTest
@testable import SwiftAgentCore
@testable import SwiftAgentOpenAI
@testable import SwiftAgentAnthropic

/// Tests for the OpenAI and Anthropic adapter export functions.
final class AdapterTests: XCTestCase {
    private func sampleDescriptor() -> MCPToolDescriptor {
        MCPToolDescriptor(
            name: "create_note",
            description: "Create a new note with a title and body.",
            inputSchema: MCPSchema.object(
                properties: [
                    "title": .string(description: "The note's title"),
                    "body": .string(description: "Markdown body"),
                    "pinned": .boolean(description: "Pin to top")
                ],
                required: ["title", "body"],
                additionalProperties: false
            ),
            annotations: MCPToolAnnotations(readOnly: false, idempotent: false)
        )
    }

    // MARK: - OpenAI

    func testOpenAIExportProducesValidStructure() {
        let result = OpenAIToolExport.export([sampleDescriptor()])
        guard let tools = result.arrayValue, let first = tools.first else {
            XCTFail("Expected array with one element")
            return
        }
        XCTAssertEqual(first["type"], .string("function"))
        XCTAssertEqual(first["function"]?["name"], .string("create_note"))
        XCTAssertNotNil(first["function"]?["description"])
        XCTAssertNotNil(first["function"]?["parameters"])
    }

    func testOpenAIExportPreservesParameterSchema() {
        let result = OpenAIToolExport.export([sampleDescriptor()])
        let params = result[0]?["function"]?["parameters"]
        XCTAssertNotNil(params?["properties"]?["title"])
        XCTAssertNotNil(params?["properties"]?["body"])
        XCTAssertNotNil(params?["properties"]?["pinned"])
        XCTAssertEqual(params?["required"]?.arrayValue?.count, 2)
    }

    func testOpenAIExportHandlesEmptyDescriptorList() {
        let result = OpenAIToolExport.export([])
        XCTAssertEqual(result, .array([]))
    }

    // MARK: - Anthropic

    func testAnthropicExportProducesValidStructure() {
        let result = AnthropicToolExport.export([sampleDescriptor()])
        guard let tools = result.arrayValue, let first = tools.first else {
            XCTFail("Expected array with one element")
            return
        }
        XCTAssertEqual(first["name"], .string("create_note"))
        XCTAssertNotNil(first["description"])
        XCTAssertNotNil(first["input_schema"])
    }

    func testAnthropicExportUsesInputSchemaKey() {
        let result = AnthropicToolExport.export([sampleDescriptor()])
        let schema = result[0]?["input_schema"]
        XCTAssertNotNil(schema?["properties"]?["title"])
        XCTAssertNil(result[0]?["parameters"], "Anthropic uses input_schema, not parameters")
    }

    func testAnthropicExportHandlesEmptyDescriptorList() {
        let result = AnthropicToolExport.export([])
        XCTAssertEqual(result, .array([]))
    }

    // MARK: - Cross-format consistency

    func testBothAdaptersPreserveSameToolName() {
        let desc = sampleDescriptor()
        let openai = OpenAIToolExport.export([desc])
        let anthropic = AnthropicToolExport.export([desc])
        let openaiName = openai[0]?["function"]?["name"]
        let anthropicName = anthropic[0]?["name"]
        XCTAssertEqual(openaiName, anthropicName)
    }
}
