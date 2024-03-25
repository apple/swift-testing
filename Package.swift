// swift-tools-version: 5.10

//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "swift-testing",

  platforms: [
    .macOS(.v10_15),
    .iOS(.v13),
    .watchOS(.v6),
    .tvOS(.v13),
    .macCatalyst(.v13),
    .visionOS(.v1),
  ],

  products: [
    .library(
      name: "Testing",
      targets: ["Testing"]
    ),
  ],

  dependencies: [
    .package(url: "https://github.com/apple/swift-syntax.git", from: "510.0.1"),
  ],

  targets: [
    .target(
      name: "Testing",
      dependencies: [
        "TestingInternals",
        "TestingMacros",
      ],
      cxxSettings: .packageSettings,
      swiftSettings: .packageSettings
    ),
    .testTarget(
      name: "TestingTests",
      dependencies: [
        "Testing",
        "_Testing_Foundation",
      ],
      swiftSettings: .packageSettings
    ),

    .macro(
      name: "TestingMacros",
      dependencies: [
        .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
      ],
      swiftSettings: .packageSettings
    ),

    // "Support" targets: These contain C family code and are used exclusively
    // by other targets above, not directly included in product libraries.
    .target(
      name: "TestingInternals",
      cxxSettings: .packageSettings
    ),

    // Cross-module overlays (unsupported)
    .target(
      name: "_Testing_Foundation",
      dependencies: [
        "Testing",
      ],
      swiftSettings: .packageSettings
    ),
  ],

  cxxLanguageStandard: .cxx20
)

// BUG: swift-package-manager-#6367
#if !os(Windows)
package.targets.append(contentsOf: [
  .testTarget(
    name: "TestingMacrosTests",
    dependencies: [
      "Testing",
      "TestingMacros",
    ],
    swiftSettings: .packageSettings
  )
])
#endif

/// Whether this package is building for distribution.
///
/// This can be used to conditionalize certain settings which are not intended
/// for use when building the package for distribution to end users.
/// Non-distribution (i.e. development-only) builds may enable things
/// like stricter compiler features which are unsupported or inappropriate for
/// client builds.
let isBuildingForDistribution = false

extension Array where Element == PackageDescription.SwiftSetting {
  /// Settings intended to be applied to every Swift target in this package.
  /// Analogous to project-level build settings in an Xcode project.
  static var packageSettings: Self {
    var settings = availabilityMacroSettings + [
      .enableExperimentalFeature("StrictConcurrency"),
      .enableUpcomingFeature("ExistentialAny"),

      .enableExperimentalFeature("AccessLevelOnImport"),
      .enableUpcomingFeature("InternalImportsByDefault"),

      .define("SWT_TARGET_OS_APPLE", .when(platforms: [.macOS, .iOS, .macCatalyst, .watchOS, .tvOS, .visionOS])),

      .define("SWT_NO_FILE_IO", .when(platforms: [.wasi])),
    ]

    if !isBuildingForDistribution {
      settings.append(contentsOf: developmentOnlySettings)
    }

    return settings
  }

  /// Settings which define commonly-used OS availability macros.
  ///
  /// These leverage a pseudo-experimental feature in the Swift compiler for
  /// setting availability definitions, which was added in
  /// [apple/swift#65218](https://github.com/apple/swift/pull/65218).
  private static var availabilityMacroSettings: Self {
    [
      .enableExperimentalFeature("AvailabilityMacro=_mangledTypeNameAPI:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0"),
      .enableExperimentalFeature("AvailabilityMacro=_backtraceAsyncAPI:macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0"),
      .enableExperimentalFeature("AvailabilityMacro=_clockAPI:macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0"),
      .enableExperimentalFeature("AvailabilityMacro=_regexAPI:macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0"),
      .enableExperimentalFeature("AvailabilityMacro=_swiftVersionAPI:macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0"),

      .enableExperimentalFeature("AvailabilityMacro=_distantFuture:macOS 99.0, iOS 99.0, watchOS 99.0, tvOS 99.0"),
    ]
  }

  /// Settings which are useful during development, but should not be included
  /// when building for distribution.
  private static var developmentOnlySettings: Self {
    [
      .unsafeFlags(["-require-explicit-sendable"]),
      .unsafeFlags(["-include-spi-symbols"]),
    ]
  }
}

extension Array where Element == PackageDescription.CXXSetting {
  /// Settings intended to be applied to every C++ target in this package.
  /// Analogous to project-level build settings in an Xcode project.
  static var packageSettings: Self {
    [
      .define("_SWT_TESTING_LIBRARY_VERSION", to: #""unknown (Swift 5.10 toolchain)""#),
    ]
  }
}
