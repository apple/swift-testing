// swift-tools-version: 6.3

//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023–2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import PackageDescription
import CompilerPluginSupport
#if !canImport(Foundation)
import Foundation
#endif

/// Information about the current state of the package's git repository.
let git = Context.gitInformation

/// Whether or not this package is being built for development rather than
/// distribution as a package dependency.
let buildingForDevelopment = (git?.currentTag == nil)

/// Whether or not to use package dependencies checked out next to the testing
/// library's package directory instead of downloading them on demand.
let useLocalDependencies = Context.environment["SWIFTCI_USE_LOCAL_DEPS"] != nil

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

  platforms: !buildingForEmbedded ? [
    .macOS(.v14),
    .iOS(.v17),
    .watchOS(.v10),
    .tvOS(.v17),
    .macCatalyst(.v17),
    .visionOS(.v1),
  ] : [
    // Open-source main-branch toolchains (currently required to build this
    // package for Embedded Swift) have higher Apple platform deployment
    // targets than we would otherwise require.
    .macOS(.v14),
    .iOS(.v18),
    .watchOS(.v10),
    .tvOS(.v18),
    .macCatalyst(.v18),
    .visionOS(.v1),
  ],
  products: {
    var result = [Product]()

#if os(Windows)
    result += [
      .library(
        name: "Testing",
        type: .dynamic, // needed so Windows exports ABI entry point symbols
        targets: ["Testing"]
      )
    ]
#else
    result += [
      .library(
        name: "Testing",
        targets: ["Testing"]
      )
    ]
#endif

    result += [
      .library(
        name: "_TestDiscovery",
        type: .static,
        targets: ["_TestDiscovery"]
      ),
      .executable(
        name: "swift-testing-harness",
        targets: ["swift-testing-harness"]
      ),
    ]

#if DEBUG
    // Build _TestingInterop for debugging/testing purposes only. It is
    // important that clients do not link to this product/target.
    result += [
      .library(
        name: "_TestingInterop_DO_NOT_USE",
        targets: ["_TestingInterop_DO_NOT_USE"]
      )
    ]
#endif

    return result
  }(),

  dependencies: !useLocalDependencies ? [
    // swift-syntax periodically publishes a new tag with a suffix of the format
    // "-prerelease-YYYY-MM-DD". We always want to use the most recent tag
    // associated with a particular Swift version, without needing to hardcode
    // an exact tag and manually keep it up-to-date. Specifying the suffix
    // "-latest" on this dependency is a workaround which causes Swift package
    // manager to use the lexicographically highest-sorted tag with the
    // specified semantic version, meaning the most recent "prerelease" tag will
    // always be used.
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "605.0.0-latest"),

    // Add a dependency on Swift Argument Parser. Note that the rest of the
    // toolchain (as of this writing) uses 1.5.x, so we match that; if the
    // toolchain updates its dependency, please update the version number here
    // and in Sources/Harness/CMakeLists.txt.
    .package(url: "https://github.com/apple/swift-argument-parser.git", .upToNextMajor(from: "1.5.0")),
  ] : [
    .package(path: "../swift-syntax"),
    .package(path: "../swift-argument-parser"),
  ],

  targets: [
    .target(
      name: "Testing",
      dependencies: [
        "_TestDiscovery",
        "_TestingInternals",
      ] + {
        // TODO: get macro target building for host when the target is embedded
        buildingForEmbedded ? [] : ["TestingMacros"]
      }(),
      exclude: ["CMakeLists.txt", "Testing.swiftcrossimport"],
      linkerSettings: [
        .linkedLibrary("execinfo", .when(platforms: [.custom("freebsd"), .openbsd])),
        .linkedLibrary("_TestingInterop"),
      ]
    ),
    .testTarget(
      name: "TestingTests",
      dependencies: [
        "Testing",
        "_Testing_AppKit",
        "_Testing_CoreGraphics",
        "_Testing_CoreImage",
        "_Testing_CoreTransferable",
        "_Testing_Foundation",
        "_Testing_UIKit",
        "_Testing_WinSDK",
        "MemorySafeTestingTests",
      ],
      linkerSettings: [
        .linkedLibrary("util", .when(platforms: [.openbsd]))
      ]
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
      swiftSettings: [.strictMemorySafety()]
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
      swiftSettings: [
        // The only target which needs the ability to import this macro
        // implementation target's module is its unit test target. Users of the
        // macros this target implements use them via their declarations in the
        // Testing module. This target's module is never distributed to users,
        // but as an additional guard against accidental misuse, this specifies
        // the unit test target as the only allowable client.
        .unsafeFlags(["-Xfrontend", "-allowable-client", "-Xfrontend", "TestingMacrosTests"]),
      ]
    ),

    // "Support" targets: These targets are not meant to be used directly by
    // test authors.
    .target(
      name: "_TestingInternals",
      exclude: ["CMakeLists.txt"]
    ),
    .target(
      name: "_TestDiscovery",
      dependencies: ["_TestingInternals",],
      exclude: ["CMakeLists.txt"]
    ),
    .target(
      // Build _TestingInterop for debugging/testing purposes only. It is
      // important that clients do not link to this product/target.
      name: "_TestingInterop_DO_NOT_USE",
      dependencies: ["_TestingInternals",],
      path: "Sources/_TestingInterop",
      exclude: ["CMakeLists.txt"]
    ),

    // Cross-import overlays (not supported by Swift Package Manager)
    .target(
      name: "_Testing_AppKit",
      dependencies: [
        "Testing",
        "_Testing_CoreGraphics",
      ],
      path: "Sources/Overlays/_Testing_AppKit",
      exclude: ["CMakeLists.txt"]
    ),
    .target(
      name: "_Testing_CoreGraphics",
      dependencies: [
        "Testing",
      ],
      path: "Sources/Overlays/_Testing_CoreGraphics",
      exclude: ["CMakeLists.txt"]
    ),
    .target(
      name: "_Testing_CoreImage",
      dependencies: [
        "Testing",
        "_Testing_CoreGraphics",
      ],
      path: "Sources/Overlays/_Testing_CoreImage",
      exclude: ["CMakeLists.txt"]
    ),
    .target(
      name: "_Testing_CoreTransferable",
      dependencies: [
        "Testing",
      ],
      path: "Sources/Overlays/_Testing_CoreTransferable",
      exclude: ["CMakeLists.txt"]
    ),
    .target(
      name: "_Testing_Foundation",
      dependencies: [
        "_TestingInternals",
        "Testing",
      ],
      path: "Sources/Overlays/_Testing_Foundation",
      exclude: ["CMakeLists.txt"]
    ),
    .target(
      name: "_Testing_UIKit",
      dependencies: [
        "Testing",
        "_Testing_CoreGraphics",
        "_Testing_CoreImage",
      ],
      path: "Sources/Overlays/_Testing_UIKit",
      exclude: ["CMakeLists.txt"]
    ),
    .target(
      name: "_Testing_WinSDK",
      dependencies: [
        "Testing",
      ],
      path: "Sources/Overlays/_Testing_WinSDK",
      exclude: ["CMakeLists.txt"]
    ),

    // Testing harness: a process that runs in between a host like SwiftPM and
    // the actual test process(es) and which manages interactions between them.
    .executableTarget(
      name: "swift-testing-harness",
      dependencies: [
        "Testing",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/Harness"
    ),

    // Utility targets: These are utilities intended for use when developing
    // this package, not for distribution.
    .executableTarget(
      name: "SymbolShowcase",
      dependencies: [
        "Testing",
      ]
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
    ]
  )
])
#endif

// Add package-wide settings to all targets. IMPORTANT: Keep this assignment
// after all target declarations!
package.targets = package.targets.map { target in
  var swiftSettings = target.swiftSettings ?? []
  swiftSettings += .packageSettings(for: target)
  target.swiftSettings = swiftSettings

  var cSettings = target.cSettings ?? []
  cSettings += .packageSettings(for: target)
  target.cSettings = cSettings

  var cxxSettings = target.cxxSettings ?? []
  cxxSettings += .packageSettings(for: target)
  target.cxxSettings = cxxSettings

  return target
}

extension PackageDescription.Target {
  /// Whether or not this target is a test target.
  ///
  /// - Note: This property overrides the property of the same name declared in
  ///   Swift Package Manager.
  var isTest: Bool {
    type == .test || name.hasSuffix("Tests")
  }
}

extension BuildSettingCondition {
  /// A build setting condition representing all Apple or non-Apple platforms.
  ///
  /// - Parameters:
  ///   - isApple: Whether or not the result represents Apple platforms.
  ///
  /// - Returns: A build setting condition that evaluates to `isApple` for Apple
  ///   platforms.
  static func whenApple(_ isApple: Bool = true) -> Self {
    .when(platforms: isApple ? .applePlatforms : .nonApplePlatforms)
  }
}

extension Array where Element == PackageDescription.Platform {
  /// All Apple platforms.
  static let applePlatforms: Self = [.macOS, .iOS, .macCatalyst, .watchOS, .tvOS, .visionOS]

  /// All non-Apple platforms.
  static let nonApplePlatforms: Self = [.linux, .custom("freebsd"), .openbsd, .windows, .wasi, .android]
}

extension Array where Element == PackageDescription.SwiftSetting {
  /// Settings intended to be applied to every Swift target in this package.
  /// Analogous to project-level build settings in an Xcode project.
  static func packageSettings(for target: PackageDescription.Target) -> Self {
    var result = availabilityMacroSettings

    // treatWarning(..., as: .warning) cannot be used in packages which are
    // used as dependencies, since the package manager suppresses all warnings
    // for dependencies. (See: rdar://170562285)
    if buildingForDevelopment {
      result.append(.treatWarning("ExplicitSendable", as: .warning))
    }

    if buildingForEmbedded && target.type != .macro {
      result.append(.enableExperimentalFeature("Embedded"))

      // Swift's concurrency module is not implicitly imported when building for
      // Embedded, so we must explicitly import it since this project uses
      // async and other concurrency-related language features.
      result.append(.unsafeFlags(["-Xfrontend", "-import-module", "-Xfrontend", "_Concurrency"]))
    }

    // Define a compiler condition so we can discover at macro expansion time if
    // we're accidentally expanding our own macros in Swift Testing.
    if !target.isTest {
      result += [
        .define("SWT_BUILDING_SWIFT_TESTING_CONTENT"),
      ]
    }

    result += [
      .enableUpcomingFeature("ExistentialAny"),

      .enableExperimentalFeature("AccessLevelOnImport"),
      .enableUpcomingFeature("InternalImportsByDefault"),

      .enableUpcomingFeature("MemberImportVisibility"),

      // Enabled to allow tests to be added to ~Escapable suites.
      .enableExperimentalFeature("Lifetimes"),

      // Enabled to allow us to forward-declare functions in the Platform
      // Abstraction Layer.
      .enableExperimentalFeature("Extern"),

      .enableUpcomingFeature("InferIsolatedConformances"),

      // When building as a package, the macro plugin always builds as an
      // executable rather than a library.
      .define("SWT_NO_LIBRARY_MACRO_PLUGINS"),

      .define("SWT_TARGET_OS_APPLE", .whenApple()),
    ]

    result.appendFeatureFlags()

    if !target.isTest {
      if target.name == "_Testing_Foundation" {
        // The Foundation module only has Library Evolution enabled on Apple
        // platforms, and since this target's module publicly imports Foundation,
        // it can only enable Library Evolution itself on those platforms.
        result += enableLibraryEvolution(.whenApple())
      } else if target.type == .regular {
        result += enableLibraryEvolution()
      }
      result += moduleABIName(target.name)
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
      .enableExperimentalFeature("AvailabilityMacro=_uttypesAPI:macOS 11.0, iOS 14.0, watchOS 7.0, tvOS 14.0"),
      .enableExperimentalFeature("AvailabilityMacro=_clockAPI:macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0"),
      .enableExperimentalFeature("AvailabilityMacro=_stringInitValidatingAPI:macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"),
      .enableExperimentalFeature("AvailabilityMacro=_typedThrowsAPI:macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"),
      .enableExperimentalFeature("AvailabilityMacro=_transferableAPI:macOS 15.2, iOS 18.2, watchOS 11.2, tvOS 18.2, visionOS 2.2"),
      .enableExperimentalFeature("AvailabilityMacro=_castingWithNonCopyableGenerics:macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0"),
      .enableExperimentalFeature("AvailabilityMacro=_objcCopyImageHeadersAPI:macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0"),

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

    if buildingForDevelopment && !buildingForEmbedded {
      result.append(.unsafeFlags(["-enable-library-evolution"], condition))
    }

    return result
  }

  /// Create a Swift setting which specifies the module ABI name to use when
  /// building the target with the specified name.
  ///
  /// - Parameters:
  ///   - targetName The name of the target for which an ABI name should be
  ///     specified.
  ///
  /// - Returns: A Swift setting that specifies the ABI name of the module of
  ///   the target named `targetName`.
  ///
  /// This function simplifies the process of specifying a custom module ABI
  /// name for various targets in this package. The module ABI name is given a
  /// suffix for all targets in this package which emit a module that is also
  /// included in the built-in copy of Swift Testing in Swift toolchains and
  /// vendor distributions. Without this, there can be runtime collisions; for
  /// example, on Darwin platforms (where Swift uses the Objective-C runtime),
  /// a non-generic Swift class type causes a warning from the runtime about
  /// duplicate class definitions. Specifying a distinct ABI name for each
  /// module related to Swift Testing loaded into a runner process avoids this
  /// issue.
  static func moduleABIName(_ targetName: String) -> Self {
    // Workaround: Disable module ABI name customization, since it has regressed
    // building DocC documentation (see rdar://171555540).
//    [.unsafeFlags(["-module-abi-name", "\(targetName)_package"])]
    []
  }
}

extension Array where Element: _CLanguageBuildSetting {
  /// Settings intended to be applied to every C++ target in this package.
  /// Analogous to project-level build settings in an Xcode project.
  static func packageSettings(for target: PackageDescription.Target) -> Self {
    var result = Self()

    // Define a compiler condition so we can discover at macro expansion time if
    // we're accidentally expanding our own macros in Swift Testing.
    if !target.isTest {
      result += [
        .define("SWT_BUILDING_SWIFT_TESTING_CONTENT"),
      ]
    }

    result.appendFeatureFlags()

    // Capture the testing library's commit info as C++ constants.
    if let git {
      result.append(.define("SWT_TESTING_LIBRARY_COMMIT_HASH", to: #""\#(git.currentCommit)""#))
      if git.hasUncommittedChanges {
        result.append(.define("SWT_TESTING_LIBRARY_COMMIT_MODIFIED", to: "1"))
      }
    } else if let gitHubSHA = Context.environment["GITHUB_SHA"] {
      // When building in GitHub Actions, the git command may fail to get us the
      // commit hash, so check if GitHub shared it with us instead.
      result.append(.define("SWT_TESTING_LIBRARY_COMMIT_HASH", to: #""\#(gitHubSHA)""#))
    }

    return result
  }
}

extension Array where Element: _LanguageBuildSetting {
  /// Append defines for feature flags.
  mutating func appendFeatureFlags() {
    // The list of defines to set. Each may have associated conditions:
    //
    // - platforms: The list of platforms, if any, to include in a build setting
    //   condition for this define.
    // - embedded: Whether this define should be set unconditionally when
    //   building for Embedded. (This is not currently expressible as a build
    //   setting conditional.)
    let defines: [String: (platforms: [Platform]?, embedded: Bool)] = [
      "SWT_NO_EXIT_TESTS": (platforms: [.iOS, .watchOS, .tvOS, .visionOS, .wasi, .android], embedded: true),
      "SWT_NO_PROCESS_SPAWNING": (platforms: [.iOS, .watchOS, .tvOS, .visionOS, .wasi, .android], embedded: true),
      "SWT_NO_SNAPSHOT_TYPES": (platforms: .nonApplePlatforms, embedded: true),
      "SWT_NO_DYNAMIC_LINKING": (platforms: [.wasi], embedded: true),
      "SWT_NO_PIPES": (platforms: [.wasi], embedded: true),
      "SWT_NO_FOUNDATION_FILE_COORDINATION": (platforms: .nonApplePlatforms, embedded: true),
      "SWT_NO_IMAGE_ATTACHMENTS": (platforms: [.linux, .custom("freebsd"), .openbsd, .wasi, .android], embedded: true),
      "SWT_NO_ENVIRONMENT_VARIABLES": (platforms: .none, embedded: true),
      "SWT_NO_FILE_IO": (platforms: .none, embedded: true),
      "SWT_NO_FILE_CLONING": (platforms: [.openbsd, .wasi, .android], embedded: true),
      "SWT_NO_ABI_ENTRY_POINT": (platforms: .none, embedded: true),
      "SWT_NO_CODABLE": (platforms: .none, embedded: true),
      "SWT_NO_INTEROP": (platforms: .none, embedded: true),
      "SWT_NO_HARNESS": (platforms: [.iOS, .watchOS, .tvOS, .visionOS, .wasi, .android], embedded: true),
      "SWT_NO_UNSTRUCTURED_TASKS": (platforms: .none, embedded: true),
      "SWT_NO_GLOBAL_ACTORS": (platforms: .none, embedded: true),
      "SWT_NO_SUSPENDING_CLOCK": (platforms: .none, embedded: true),
      "SWT_NO_BACKTRACE_SYMBOLICATION": (platforms: .none, embedded: true),

      "SWT_NO_LIBDISPATCH": (platforms: .none, embedded: true),
      "SWT_NO_FOUNDATION": (platforms: .none, embedded: true),
    ]

    // Let the environment block override our settings above.
    let environmentVariables = Context.environment
      .filter { $0.key.starts(with: "SWT_NO_") }
      .compactMapValues { value in
#if !canImport(Foundation)
        (value as NSString).boolValue
#else
        Bool(value) ?? UInt64(value).map { $0 != 0 }
#endif
      }

    for (name, environmentVariable) in environmentVariables {
      // The environment variable is set. If the value is `true`, that means
      // the "NO" flag should be set unconditionally. If the value is `false`,
      // that means the flag should _not_ be set.
      if environmentVariable {
        append(.define(name, nil))
      }
    }

    for (name, details) in defines {
      if environmentVariables[name] != nil {
        // Handled in the loop above. We don't handle it here because it would
        // limit us to only the environment variables that we've explicitly
        // configured in the table above, but that table is not comprehensive.
      } else if !buildingForEmbedded {
        if let platforms = details.platforms {
          append(.define(name, .when(platforms: platforms)))
        } else {
          // Since there was no condition and we're not building for Embedded,
          // the intention was to never match so don't append this define.
        }
      } else if details.embedded {
        // Since we're building for Embedded and this define is supposed to be
        // included unconditionally when building as such, append it.
        append(.define(name, nil))
      }
    }
  }
}

/// A protocol representing a setting for a package target.
///
/// This abstraction facilitates utilities which simplify specifying common
/// settings across targets of different language types.
private protocol _LanguageBuildSetting {
  /// Defines a value for a macro.
  ///
  /// - Parameters:
  ///   - name: The name of the macro.
  ///   - condition: A condition that restricts the application of the build
  ///     setting.
  ///
  /// - Returns: An instance of this setting.
  static func define(_ name: String, _ condition: BuildSettingCondition?) -> Self
}

extension _LanguageBuildSetting {
  static func define(_ name: String) -> Self {
    .define(name, nil)
  }
}

private protocol _CLanguageBuildSetting: _LanguageBuildSetting {
  /// Defines a value for a macro.
  ///
  /// - Parameters:
  ///   - name: The name of the macro.
  ///   - value: The value of the macro.
  ///   - condition: A condition that restricts the application of the build
  ///     setting.
  ///
  /// - Returns: An instance of this setting.
  static func define(_ name: String, to value: String?, _ condition: BuildSettingCondition?) -> Self
}

extension _CLanguageBuildSetting {
  static func define(_ name: String, _ condition: PackageDescription.BuildSettingCondition?) -> Self {
    .define(name, to: nil, condition)
  }

  static func define(_ name: String, to value: String? = nil, _ condition: BuildSettingCondition? = nil) -> Self {
    .define(name, to: value, condition)
  }
}

extension PackageDescription.SwiftSetting: _LanguageBuildSetting {}
extension PackageDescription.CSetting: _CLanguageBuildSetting {}
extension PackageDescription.CXXSetting: _CLanguageBuildSetting {}
