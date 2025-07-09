// swift-tools-version: 6.1

//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import PackageDescription
import CompilerPluginSupport

/// Information about the current state of the package's git repository.
let git = Context.gitInformation

/// Whether or not this package is being built for development rather than
/// distribution as a package dependency.
let buildingForDevelopment = (git?.currentTag == nil)

/// Whether or not this package is being built for Embedded Swift.
///
/// This value is `true` if `SWT_EMBEDDED` is set in the environment to `true`
/// when `swift build` is invoked. This inference is experimental and is subject
/// to change in the future.
///
/// - Bug: There is currently no way for us to tell if we are being asked to
///   build for an Embedded Swift target at the package manifest level.
///   ([swift-syntax-#8431](https://github.com/swiftlang/swift-package-manager/issues/8431))
let buildingForEmbedded: Bool = {
  guard let envvar = Context.environment["SWT_EMBEDDED"] else {
    return false
  }
  return Bool(envvar) ?? ((Int(envvar) ?? 0) != 0)
}()

let package = Package(
  name: "swift-testing",

  platforms: {
    if !buildingForEmbedded {
      [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
        .macCatalyst(.v13),
        .visionOS(.v1),
      ]
    } else {
      // Open-source main-branch toolchains (currently required to build this
      // package for Embedded Swift) have higher Apple platform deployment
      // targets than we would otherwise require.
      [
        .macOS(.v14),
        .iOS(.v18),
        .watchOS(.v10),
        .tvOS(.v18),
        .macCatalyst(.v18),
        .visionOS(.v1),
      ]
    }
  }(),

  products: {
    var result = [Product]()

#if os(Windows)
    result.append(
      .library(
        name: "Testing",
        type: .dynamic, // needed so Windows exports ABI entry point symbols
        targets: ["Testing"]
      )
    )
#else
    result.append(
      .library(
        name: "Testing",
        targets: ["Testing"]
      )
    )
#endif

    result += [
      .library(
        name: "_Testing_ExperimentalImageAttachments",
        targets: [
          "_Testing_AppKit",
          "_Testing_CoreGraphics",
          "_Testing_CoreImage",
        ]
      )
    ]

    result.append(
      .library(
        name: "_TestDiscovery",
        type: .static,
        targets: ["_TestDiscovery"]
      )
    )

    return result
  }(),

  traits: [
    .trait(
      name: "ExperimentalExitTestValueCapture",
      description: "Enable experimental support for capturing values in exit tests"
    ),
  ],

  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0-latest"),
  ],

  targets: [
    .target(
      name: "Testing",
      dependencies: [
        "_TestDiscovery",
        "_TestingInternals",
        "TestingMacros",
      ],
      exclude: ["CMakeLists.txt", "Testing.swiftcrossimport"],
      cxxSettings: .packageSettings,
      swiftSettings: .packageSettings + .enableLibraryEvolution(),
      linkerSettings: [
        .linkedLibrary("execinfo", .when(platforms: [.custom("freebsd"), .openbsd]))
      ]
    ),
    .testTarget(
      name: "TestingTests",
      dependencies: [
        "Testing",
        "_Testing_AppKit",
        "_Testing_CoreGraphics",
        "_Testing_CoreImage",
        "_Testing_Foundation",
        "MemorySafeTestingTests",
      ],
      swiftSettings: .packageSettings
    ),

    // Use a plain `.target` instead of a `.testTarget` to avoid the unnecessary
    // overhead of having a separate test target for this module. Conceptually,
    // the content in this module is no different than content which would
    // typically be placed in the `TestingTests` target, except this content
    // needs the (module-wide) strict memory safety feature to be enabled.
    .target(
      name: "MemorySafeTestingTests",
      dependencies: [
        "Testing",
      ],
      path: "Tests/_MemorySafeTestingTests",
      swiftSettings: .packageSettings + .strictMemorySafety
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
      exclude: ["CMakeLists.txt"],
      swiftSettings: .packageSettings + {
        var result = [PackageDescription.SwiftSetting]()

        // The only target which needs the ability to import this macro
        // implementation target's module is its unit test target. Users of the
        // macros this target implements use them via their declarations in the
        // Testing module. This target's module is never distributed to users,
        // but as an additional guard against accidental misuse, this specifies
        // the unit test target as the only allowable client.
        if buildingForDevelopment {
          result.append(.unsafeFlags(["-Xfrontend", "-allowable-client", "-Xfrontend", "TestingMacrosTests"]))
        }

        return result
      }()
    ),

    // "Support" targets: These targets are not meant to be used directly by
    // test authors.
    .target(
      name: "_TestingInternals",
      exclude: ["CMakeLists.txt"],
      cxxSettings: .packageSettings
    ),
    .target(
      name: "_TestDiscovery",
      dependencies: ["_TestingInternals",],
      exclude: ["CMakeLists.txt"],
      cxxSettings: .packageSettings,
      swiftSettings: .packageSettings + .enableLibraryEvolution()
    ),

    // Cross-import overlays (not supported by Swift Package Manager)
    .target(
      name: "_Testing_AppKit",
      dependencies: [
        "Testing",
        "_Testing_CoreGraphics",
      ],
      path: "Sources/Overlays/_Testing_AppKit",
      swiftSettings: .packageSettings + .enableLibraryEvolution()
    ),
    .target(
      name: "_Testing_CoreGraphics",
      dependencies: [
        "Testing",
      ],
      path: "Sources/Overlays/_Testing_CoreGraphics",
      swiftSettings: .packageSettings + .enableLibraryEvolution()
    ),
    .target(
      name: "_Testing_CoreImage",
      dependencies: [
        "Testing",
        "_Testing_CoreGraphics",
      ],
      path: "Sources/Overlays/_Testing_CoreImage",
      swiftSettings: .packageSettings + .enableLibraryEvolution()
    ),
    .target(
      name: "_Testing_Foundation",
      dependencies: [
        "Testing",
      ],
      path: "Sources/Overlays/_Testing_Foundation",
      exclude: ["CMakeLists.txt"],
      // The Foundation module only has Library Evolution enabled on Apple
      // platforms, and since this target's module publicly imports Foundation,
      // it can only enable Library Evolution itself on those platforms.
      swiftSettings: .packageSettings + .enableLibraryEvolution(.whenApple())
    ),

    // Utility targets: These are utilities intended for use when developing
    // this package, not for distribution.
    .executableTarget(
      name: "SymbolShowcase",
      dependencies: [
        "Testing",
      ],
      swiftSettings: .packageSettings
    ),
  ],

  cxxLanguageStandard: .cxx20
)

// BUG: swift-package-manager-#6367
#if !os(Windows) && !os(FreeBSD) && !os(OpenBSD)
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

extension BuildSettingCondition {
  /// Creates a build setting condition that evaluates to `true` for Embedded
  /// Swift.
  ///
  /// - Parameters:
  ///   - nonEmbeddedCondition: The value to return if the target is not
  ///     Embedded Swift. If `nil`, the build condition evaluates to `false`.
  ///
  /// - Returns: A build setting condition that evaluates to `true` for Embedded
  ///   Swift or is equal to `nonEmbeddedCondition` for non-Embedded Swift.
  static func whenEmbedded(or nonEmbeddedCondition: @autoclosure () -> Self? = nil) -> Self? {
    if !buildingForEmbedded {
      if let nonEmbeddedCondition = nonEmbeddedCondition() {
        nonEmbeddedCondition
      } else {
        // The caller did not supply a fallback. Specify a non-existent platform
        // to ensure this condition never matches.
        .when(platforms: [.custom("DoesNotExist")])
      }
    } else {
      // Enable unconditionally because the target is Embedded Swift.
      nil
    }
  }

  /// A build setting condition representing all Apple or non-Apple platforms.
  ///
  /// - Parameters:
  ///   - isApple: Whether or not the result represents Apple platforms.
  ///
  /// - Returns: A build setting condition that evaluates to `isApple` for Apple
  ///   platforms.
  static func whenApple(_ isApple: Bool = true) -> Self {
    if isApple {
      .when(platforms: [.macOS, .iOS, .macCatalyst, .watchOS, .tvOS, .visionOS])
    } else {
      .when(platforms: [.linux, .custom("freebsd"), .openbsd, .windows, .wasi, .android])
    }
  }
}

extension Array where Element == PackageDescription.SwiftSetting {
  /// Settings intended to be applied to every Swift target in this package.
  /// Analogous to project-level build settings in an Xcode project.
  static var packageSettings: Self {
    var result = availabilityMacroSettings

    if buildingForDevelopment {
      result.append(.unsafeFlags(["-require-explicit-sendable"]))
    }

    if buildingForEmbedded {
      result.append(.enableExperimentalFeature("Embedded"))
    }

    result += [
      .enableUpcomingFeature("ExistentialAny"),

      .enableExperimentalFeature("AccessLevelOnImport"),
      .enableUpcomingFeature("InternalImportsByDefault"),

      .enableUpcomingFeature("MemberImportVisibility"),

      // This setting is enabled in the package, but not in the toolchain build
      // (via CMake). Enabling it is dependent on acceptance of the @section
      // proposal via Swift Evolution.
      //
      // FIXME: Re-enable this once a CI blocker is resolved:
      // https://github.com/swiftlang/swift-testing/issues/1138.
//      .enableExperimentalFeature("SymbolLinkageMarkers"),

      // This setting is no longer needed when building with a 6.2 or later
      // toolchain now that SE-0458 has been accepted and implemented, but it is
      // needed in order to preserve support for building with 6.1 development
      // snapshot toolchains. (Production 6.1 toolchains can build the testing
      // library even without this setting since this experimental feature is
      // _suppressible_.) This setting can be removed once the minimum supported
      // toolchain for building the testing library is ≥ 6.2. It is not needed
      // in the CMake settings since that is expected to build using a
      // new-enough toolchain.
      .enableExperimentalFeature("AllowUnsafeAttribute"),

      .enableUpcomingFeature("InferIsolatedConformances"),

      // When building as a package, the macro plugin always builds as an
      // executable rather than a library.
      .define("SWT_NO_LIBRARY_MACRO_PLUGINS"),

      .define("SWT_TARGET_OS_APPLE", .whenApple()),

      .define("SWT_NO_EXIT_TESTS", .whenEmbedded(or: .when(platforms: [.iOS, .watchOS, .tvOS, .visionOS, .wasi, .android]))),
      .define("SWT_NO_PROCESS_SPAWNING", .whenEmbedded(or: .when(platforms: [.iOS, .watchOS, .tvOS, .visionOS, .wasi, .android]))),
      .define("SWT_NO_SNAPSHOT_TYPES", .whenEmbedded(or: .whenApple(false))),
      .define("SWT_NO_DYNAMIC_LINKING", .whenEmbedded(or: .when(platforms: [.wasi]))),
      .define("SWT_NO_PIPES", .whenEmbedded(or: .when(platforms: [.wasi]))),
      .define("SWT_NO_FOUNDATION_FILE_COORDINATION", .whenEmbedded(or: .whenApple(false))),

      .define("SWT_NO_LEGACY_TEST_DISCOVERY", .whenEmbedded()),
      .define("SWT_NO_LIBDISPATCH", .whenEmbedded()),
    ]

    // Unconditionally enable 'ExperimentalExitTestValueCapture' when building
    // for development.
    if buildingForDevelopment {
      result += [
        .define("ExperimentalExitTestValueCapture")
      ]
    }

    return result
  }

  /// Settings which define commonly-used OS availability macros.
  ///
  /// These leverage a pseudo-experimental feature in the Swift compiler for
  /// setting availability definitions, which was added in
  /// [swift#65218](https://github.com/swiftlang/swift/pull/65218).
  private static var availabilityMacroSettings: Self {
    [
      .enableExperimentalFeature("AvailabilityMacro=_mangledTypeNameAPI:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0"),
      .enableExperimentalFeature("AvailabilityMacro=_uttypesAPI:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0"),
      .enableExperimentalFeature("AvailabilityMacro=_backtraceAsyncAPI:macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0"),
      .enableExperimentalFeature("AvailabilityMacro=_clockAPI:macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0"),
      .enableExperimentalFeature("AvailabilityMacro=_regexAPI:macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0"),
      .enableExperimentalFeature("AvailabilityMacro=_swiftVersionAPI:macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0"),
      .enableExperimentalFeature("AvailabilityMacro=_typedThrowsAPI:macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"),

      .enableExperimentalFeature("AvailabilityMacro=_distantFuture:macOS 99.0, iOS 99.0, watchOS 99.0, tvOS 99.0, visionOS 99.0"),
    ]
  }

  /// Create a Swift setting which enables Library Evolution.
  ///
  /// - Parameters:
  ///   - condition: A build setting condition to apply to this setting.
  ///
  /// - Returns: A Swift setting that enables Library Evolution.
  static func enableLibraryEvolution(_ condition: BuildSettingCondition? = nil) -> Self {
    var result = [PackageDescription.SwiftSetting]()

    if buildingForDevelopment {
      result.append(.unsafeFlags(["-enable-library-evolution"], condition))
    }

    return result
  }

  /// Settings necessary to enable Strict Memory Safety, introduced in
  /// [SE-0458: Opt-in Strict Memory Safety Checking](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0458-strict-memory-safety.md#swiftpm-integration).
  static var strictMemorySafety: Self {
#if compiler(>=6.2)
    // FIXME: Adopt official `.strictMemorySafety()` condition once the minimum
    // supported toolchain is 6.2.
    [.unsafeFlags(["-strict-memory-safety"])]
#else
    []
#endif
  }
}

extension Array where Element == PackageDescription.CXXSetting {
  /// Settings intended to be applied to every C++ target in this package.
  /// Analogous to project-level build settings in an Xcode project.
  static var packageSettings: Self {
    var result = Self()

    result += [
      .define("SWT_NO_EXIT_TESTS", .whenEmbedded(or: .when(platforms: [.iOS, .watchOS, .tvOS, .visionOS, .wasi, .android]))),
      .define("SWT_NO_PROCESS_SPAWNING", .whenEmbedded(or: .when(platforms: [.iOS, .watchOS, .tvOS, .visionOS, .wasi, .android]))),
      .define("SWT_NO_SNAPSHOT_TYPES", .whenEmbedded(or: .whenApple(false))),
      .define("SWT_NO_DYNAMIC_LINKING", .whenEmbedded(or: .when(platforms: [.wasi]))),
      .define("SWT_NO_PIPES", .whenEmbedded(or: .when(platforms: [.wasi]))),
      .define("SWT_NO_FOUNDATION_FILE_COORDINATION", .whenEmbedded(or: .whenApple(false))),

      .define("SWT_NO_LEGACY_TEST_DISCOVERY", .whenEmbedded()),
      .define("SWT_NO_LIBDISPATCH", .whenEmbedded()),
    ]

    // Capture the testing library's version as a C++ string constant.
    if let git {
      let testingLibraryVersion = if let tag = git.currentTag {
        tag
      } else if git.hasUncommittedChanges {
        "\(git.currentCommit) (modified)"
      } else {
        git.currentCommit
      }
      result.append(.define("SWT_TESTING_LIBRARY_VERSION", to: #""\#(testingLibraryVersion)""#))
    }

    return result
  }
}
