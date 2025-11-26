// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerlKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2)
    ],
    products: [
        .library(
            name: "PerlKit",
            targets: ["PerlKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/6over3/WasmKit", from: "0.1.6"),
        .package(url: "https://github.com/ordo-one/package-benchmark", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "PerlKit",
            dependencies: [
                .product(name: "WasmKit", package: "WasmKit"),
                .product(name: "WasmKitWASI", package: "WasmKit"),
            ],
            resources: [
                .copy("Resources/zeroperl.wasm")
            ]
        ),
        .testTarget(
            name: "PerlKitTests",
            dependencies: ["PerlKit"]
        ),
        .executableTarget(
            name: "PerlKitBenchmarks",
            dependencies: [
                "PerlKit",
                .product(name: "Benchmark", package: "package-benchmark")
            ],
            path: "Benchmarks/PerlKitBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        ),
    ]
)