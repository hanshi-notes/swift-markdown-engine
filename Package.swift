// swift-tools-version: 5.9
import PackageDescription

// MarkdownEngine — a TextKit-2 backed Markdown editor view for macOS.
//
// Embedders import `MarkdownEngine` and supply their own adapters that
// conform to the engine's service protocols (`WikiLinkResolver`,
// `EmbeddedImageProvider`, `SyntaxHighlighter`, `LatexRenderer`). The engine
// itself has zero external dependencies.
//
// There are no bundled bridge products: code-block highlighting and LaTeX
// rendering are supplied by the embedder through `SyntaxHighlighter` and
// `LatexRenderer`, using whatever libraries it already has. The package
// therefore has no external dependencies at all.
let package = Package(
    name: "MarkdownEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MarkdownEngine", targets: ["MarkdownEngine"]),
    ],
    targets: [
        .target(name: "MarkdownEngine"),
        .testTarget(
            name: "MarkdownEngineTests",
            dependencies: ["MarkdownEngine"]
        )
    ]
)
