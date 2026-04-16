// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftAgent",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .macCatalyst(.v17),
        .visionOS(.v1),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "SwiftAgent", targets: ["SwiftAgent"]),
        .library(name: "SwiftAgentCore", targets: ["SwiftAgentCore"]),
        .library(name: "SwiftAgentServer", targets: ["SwiftAgentServer"]),
        .library(name: "SwiftAgentClient", targets: ["SwiftAgentClient"]),
        .library(name: "SwiftAgentIntents", targets: ["SwiftAgentIntents"]),
        .library(name: "SwiftAgentOpenAI", targets: ["SwiftAgentOpenAI"]),
        .library(name: "SwiftAgentAnthropic", targets: ["SwiftAgentAnthropic"]),
        .library(name: "SwiftAgentFoundationModels", targets: ["SwiftAgentFoundationModels"]),
        .library(name: "SwiftAgentHTTPServer", targets: ["SwiftAgentHTTPServer"]),
        .library(name: "SwiftAgentHTTPClient", targets: ["SwiftAgentHTTPClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        // MARK: - Core

        .target(
            name: "SwiftAgentCore",
            path: "Sources/SwiftAgentCore",
            swiftSettings: strictConcurrency
        ),

        // MARK: - Server

        .target(
            name: "SwiftAgentServer",
            dependencies: ["SwiftAgentCore"],
            path: "Sources/SwiftAgentServer",
            swiftSettings: strictConcurrency
        ),

        // MARK: - Client

        .target(
            name: "SwiftAgentClient",
            dependencies: ["SwiftAgentCore"],
            path: "Sources/SwiftAgentClient",
            swiftSettings: strictConcurrency
        ),

        // MARK: - Intents bridge

        .target(
            name: "SwiftAgentIntents",
            dependencies: ["SwiftAgentCore", "SwiftAgentServer"],
            path: "Sources/SwiftAgentIntents",
            swiftSettings: strictConcurrency
        ),

        // MARK: - Macro plugin

        .macro(
            name: "SwiftAgentMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ],
            path: "Sources/SwiftAgentMacros",
            swiftSettings: strictConcurrency
        ),

        // MARK: - Umbrella (macro declarations + re-exports)

        .target(
            name: "SwiftAgent",
            dependencies: [
                "SwiftAgentCore",
                "SwiftAgentServer",
                "SwiftAgentClient",
                "SwiftAgentIntents",
                "SwiftAgentMacros"
            ],
            path: "Sources/SwiftAgent",
            swiftSettings: strictConcurrency
        ),

        // MARK: - LLM-SDK adapters

        .target(
            name: "SwiftAgentOpenAI",
            dependencies: ["SwiftAgentCore"],
            path: "Sources/SwiftAgentOpenAI",
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "SwiftAgentAnthropic",
            dependencies: ["SwiftAgentCore"],
            path: "Sources/SwiftAgentAnthropic",
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "SwiftAgentFoundationModels",
            dependencies: ["SwiftAgentCore", "SwiftAgentServer"],
            path: "Sources/SwiftAgentFoundationModels",
            swiftSettings: strictConcurrency
        ),

        // MARK: - HTTP transports

        .target(
            name: "SwiftAgentHTTPServer",
            dependencies: ["SwiftAgentCore", "SwiftAgentServer"],
            path: "Sources/SwiftAgentHTTPServer",
            swiftSettings: strictConcurrency
        ),

        .target(
            name: "SwiftAgentHTTPClient",
            dependencies: ["SwiftAgentCore", "SwiftAgentClient"],
            path: "Sources/SwiftAgentHTTPClient",
            swiftSettings: strictConcurrency
        ),

        // MARK: - Executables

        .executableTarget(
            name: "MCPTestServer",
            dependencies: ["SwiftAgentCore", "SwiftAgentServer", "SwiftAgentHTTPServer"],
            path: "Sources/MCPTestServer",
            swiftSettings: strictConcurrency
        ),

        .executableTarget(
            name: "AgentRunner",
            dependencies: [
                "SwiftAgentCore", "SwiftAgentClient",
                "SwiftAgentHTTPClient", "SwiftAgentOpenAI"
            ],
            path: "Sources/AgentRunner",
            swiftSettings: strictConcurrency
        ),

        // MARK: - Tests

        .testTarget(
            name: "SwiftAgentCoreTests",
            dependencies: [
                "SwiftAgentCore", "SwiftAgentServer", "SwiftAgentClient",
                "SwiftAgentOpenAI", "SwiftAgentAnthropic"
            ],
            path: "Tests/SwiftAgentCoreTests",
            swiftSettings: strictConcurrency
        ),

        .testTarget(
            name: "SwiftAgentMacroTests",
            dependencies: [
                "SwiftAgentMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ],
            path: "Tests/SwiftAgentMacroTests",
            swiftSettings: strictConcurrency
        )
    ]
)

var strictConcurrency: [SwiftSetting] {
    [
        .enableUpcomingFeature("StrictConcurrency"),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("BareSlashRegexLiterals"),
        .enableUpcomingFeature("ConciseMagicFile"),
        .enableUpcomingFeature("ForwardTrailingClosures"),
        .enableUpcomingFeature("ImplicitOpenExistentials")
    ]
}
