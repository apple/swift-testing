//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension ABIv0 {
  /// A type implementing the JSON encoding of ``Issue`` for the ABI entry point
  /// and event stream output.
  ///
  /// This type is not part of the public interface of the testing library. It
  /// assists in converting values to JSON; clients that consume this JSON are
  /// expected to write their own decoders.
  struct EncodedIssue: Sendable {
    /// Whether or not this issue is known to occur.
    var isKnown: Bool

    /// The location in source where this issue occurred, if available.
    var sourceLocation: SourceLocation?

    /// Any tool-specific context about the issue including the name of the tool
    /// that recorded it.
    ///
    /// When decoding using `JSONDecoder`, the value of this property is set to
    /// `nil`. Tools that need access to their context values should not use
    /// ``ABIv0/EncodedIssue`` to decode issues.
    var toolContext: (any Issue.Kind.ToolContext)?

    init(encoding issue: borrowing Issue) {
      isKnown = issue.isKnown
      sourceLocation = issue.sourceLocation
      if case let .recordedByTool(toolContext) = issue.kind {
        self.toolContext = toolContext
      }
    }
  }
}

// MARK: - Codable

extension ABIv0.EncodedIssue: Codable {
  private enum CodingKeys: String, CodingKey {
    case isKnown
    case sourceLocation
    case toolContext
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(isKnown, forKey: .isKnown)
    try container.encode(sourceLocation, forKey: .sourceLocation)
    if let toolContext {
      func encodeToolContext(_ toolContext: some Issue.Kind.ToolContext) throws {
        try container.encode(toolContext, forKey: .toolContext)
      }
      try encodeToolContext(toolContext)
    }
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    isKnown = try container.decode(Bool.self, forKey: .isKnown)
    sourceLocation = try container.decode(SourceLocation.self, forKey: .sourceLocation)
    toolContext = nil // not decoded
  }
}
