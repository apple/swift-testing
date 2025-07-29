//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

/// A namespace for ABI symbols.
@_spi(ForToolsIntegrationOnly)
public enum ABI: Sendable {}

// MARK: - ABI version abstraction

extension ABI {
  /// A protocol describing the types that represent different ABI versions.
  protocol Version: Sendable {
    /// The numeric representation of this ABI version.
    static var versionNumber: VersionNumber { get }

#if canImport(Foundation) && (!SWT_NO_FILE_IO || !SWT_NO_ABI_ENTRY_POINT)
    /// Create an event handler that encodes events as JSON and forwards them to
    /// an ABI-friendly event handler.
    ///
    /// - Parameters:
    ///   - encodeAsJSONLines: Whether or not to ensure JSON passed to
    ///     `eventHandler` is encoded as JSON Lines (i.e. that it does not
    ///     contain extra newlines.)
    ///   - eventHandler: The event handler to forward events to.
    ///
    /// - Returns: An event handler.
    ///
    /// The resulting event handler outputs data as JSON. For each event handled
    /// by the resulting event handler, a JSON object representing it and its
    /// associated context is created and is passed to `eventHandler`.
    static func eventHandler(
      encodeAsJSONLines: Bool,
      forwardingTo eventHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
    ) -> Event.Handler
#endif
  }

  /// The current supported ABI version (ignoring any experimental versions.)
  typealias CurrentVersion = v0

#if !hasFeature(Embedded)
  /// Get the type representing a given ABI version.
  ///
  /// - Parameters:
  ///   - versionNumber: The ABI version number for which a concrete type is
  ///     needed.
  ///
  /// - Returns: A type conforming to ``ABI/Version`` that represents the given
  ///   ABI version, or `nil` if no such type exists.
  static func version(forVersionNumber versionNumber: VersionNumber = ABI.CurrentVersion.versionNumber) -> (any Version.Type)? {
    switch versionNumber {
    case ABI.v6_3.versionNumber...:
      ABI.v6_3.self
    case ABI.v0.versionNumber...:
      ABI.v0.self
#if !SWT_NO_SNAPSHOT_TYPES
    case ABI.Xcode16.versionNumber:
      // Legacy support for Xcode 16. Support for this undocumented version will
      // be removed in a future update. Do not use it.
      ABI.Xcode16.self
#endif
    default:
      nil
    }
  }
#endif
}

// MARK: - Concrete ABI versions

extension ABI {
#if !SWT_NO_SNAPSHOT_TYPES
  /// A namespace and version type for Xcode&nbsp;16 compatibility.
  ///
  /// - Warning: This type will be removed in a future update.
  enum Xcode16: Sendable, Version {
    static var versionNumber: VersionNumber {
      VersionNumber(-1, 0)
    }
  }
#endif

  /// A namespace and type for ABI version 0 symbols.
  public enum v0: Sendable, Version {
    static var versionNumber: VersionNumber {
      VersionNumber(0, 0)
    }
  }

  /// A namespace and type for ABI version 6.3 symbols.
  ///
  /// @Metadata {
  ///   @Available(Swift, introduced: 6.3)
  /// }
  @_spi(Experimental)
  public enum v6_3: Sendable, Version {
    static var versionNumber: VersionNumber {
      VersionNumber(6, 3)
    }
  }
}

/// A namespace for ABI version 0 symbols.
@_spi(ForToolsIntegrationOnly)
@available(*, deprecated, renamed: "ABI.v0")
public typealias ABIv0 = ABI.v0
