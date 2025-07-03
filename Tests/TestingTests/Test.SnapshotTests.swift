//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !SWT_NO_SNAPSHOT_TYPES
@_spi(Experimental) @_spi(ForToolsIntegrationOnly) @testable import Testing

@Suite("Test.Snapshot tests")
struct Test_SnapshotTests {
#if canImport(Foundation)
  @Test("Codable")
  func codable() throws {
    let test = try #require(Test.current)
    let snapshot = Test.Snapshot(snapshotting: test)
    let decoded = try JSON.encodeAndDecode(snapshot)

    #expect(decoded.id == snapshot.id)
    #expect(decoded.name == snapshot.name)
    #expect(decoded.displayName == snapshot.displayName)
    #expect(decoded.sourceLocation == snapshot.sourceLocation)
    // FIXME: Compare traits as well, once they are included.
    #expect(decoded.parameters == snapshot.parameters)
  }
#endif

  @Test("isParameterized property")
  func isParameterized() async throws {
    do {
      let test = try #require(Test.current)
      let snapshot = Test.Snapshot(snapshotting: test)
      #expect(!snapshot.isParameterized)
    }
    do {
      let test = try #require(await testFunction(named: "parameterized(i:)", in: MainActorIsolatedTests.self))
      let snapshot = Test.Snapshot(snapshotting: test)
      #expect(snapshot.isParameterized)
    }
    do {
      let suite = try #require(await test(for: Self.self))
      let snapshot = Test.Snapshot(snapshotting: suite)
      #expect(!snapshot.isParameterized)
    }
  }

  @Test("isSuite property")
  func isSuite() async throws {
    do {
      let test = try #require(Test.current)
      let snapshot = Test.Snapshot(snapshotting: test)
      #expect(!snapshot.isSuite)
    }
    do {
      let test = try #require(await testFunction(named: "parameterized(i:)", in: MainActorIsolatedTests.self))
      let snapshot = Test.Snapshot(snapshotting: test)
      #expect(!snapshot.isSuite)
    }
    do {
      let suite = try #require(await test(for: Self.self))
      let snapshot = Test.Snapshot(snapshotting: suite)
      #expect(snapshot.isSuite)
    }
  }

  /// This is a comment that should show up in the test's `comments` property.
  @Test("comments property")
  func comments() async throws {
    let test = try #require(Test.current)
    let snapshot = Test.Snapshot(snapshotting: test)

    #expect(!snapshot.comments.isEmpty)
    #expect(snapshot.comments == test.comments)
  }

  @Test("tags property", .tags(Tag.testTag))
  func tags() async throws {
    let test = try #require(Test.current)
    let snapshot = Test.Snapshot(snapshotting: test)

    #expect(snapshot.tags.count == 1)
    #expect(snapshot.tags.first == Tag.testTag)
  }

  @Test("associatedBugs property", bug)
  func associatedBugs() async throws {
    let test = try #require(Test.current)
    let snapshot = Test.Snapshot(snapshotting: test)

    #expect(snapshot.associatedBugs.count == 1)
    #expect(snapshot.associatedBugs.first == Self.bug)
  }

  private static let bug: Bug = Bug.bug(id: 12345, "Lorem ipsum")

  @available(_clockAPI, *)
  @Test("timeLimit property", .tags(.traitRelated), _timeLimitIfAvailable(minutes: 999_999_999))
  func timeLimit() async throws {
    let test = try #require(Test.current)
    let snapshot = Test.Snapshot(snapshotting: test)

    #expect(snapshot.timeLimit == .seconds(60) * 999_999_999)
  }

  /// Create a time limit trait representing the specified number of minutes, if
  /// running on an OS which supports time limits.
  ///
  /// - Parameters:
  ///   - minutes: The number of minutes the returned time limit trait should
  ///     represent.
  ///
  /// - Returns: A time limit trait if the API is available, otherwise a
  ///   disabled trait.
  ///
  /// This is provided in order to work around a bug where traits with
  /// conditional API availability are not guarded by `@available` attributes on
  /// `@Test` functions (rdar://127811571).
  private static func _timeLimitIfAvailable(minutes: some BinaryInteger) -> any TestTrait {
    guard #available(_clockAPI, *) else {
      return .disabled(".timeLimit() not available")
    }
    return .timeLimit(.minutes(minutes))
  }
}

extension Tag {
  @Tag fileprivate static var testTag: Self
}
#endif
