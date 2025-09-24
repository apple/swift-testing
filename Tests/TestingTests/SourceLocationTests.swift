//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing

@Suite("SourceLocation Tests")
struct SourceLocationTests {
  @Test("SourceLocation.description property")
  func sourceLocationDescription() {
    let sourceLocation = #_sourceLocation
    _ = String(describing: sourceLocation)
    _ = String(reflecting: sourceLocation)
  }

  @Test("SourceLocation.fileID property")
  func sourceLocationFileID() {
    let sourceLocation = #_sourceLocation
    #expect(sourceLocation.fileID.hasSuffix("/SourceLocationTests.swift"))
  }

  @Test("SourceLocation.fileName property")
  func sourceLocationFileName() {
    var sourceLocation = #_sourceLocation
    #expect(sourceLocation.fileName == "SourceLocationTests.swift")

    sourceLocation.fileID = "FakeModule/FakeFileID"
    #expect(sourceLocation.fileName == "FakeFileID")
  }

  @Test("SourceLocation.moduleName property")
  func sourceLocationModuleName() {
    var sourceLocation = #_sourceLocation
    #expect(!sourceLocation.moduleName.contains("/"))
    #expect(!sourceLocation.moduleName.isEmpty)

    sourceLocation.fileID = "FakeModule/FakeFileID"
    #expect(sourceLocation.moduleName == "FakeModule")
  }

  @Test("SourceLocation.moduleName property with raw identifier",
    arguments: [
      ("Foo/Bar.swift", "Foo", "Bar.swift"),
      ("`Foo`/Bar.swift", "`Foo`", "Bar.swift"),
      ("`Foo.Bar`/Quux.swift", "`Foo.Bar`", "Quux.swift"),
      ("`Foo./.Bar`/Quux.swift", "`Foo./.Bar`", "Quux.swift"),
    ]
  )
  func sourceLocationModuleNameWithRawIdentifier(fileID: String, expectedModuleName: String, expectedFileName: String) throws {
    let sourceLocation = SourceLocation(fileID: fileID, filePath: "", line: 1, column: 1)
    #expect(sourceLocation.moduleName == expectedModuleName)
    #expect(sourceLocation.fileName == expectedFileName)
  }

  @Test("SourceLocation.fileID property ignores middle components")
  func sourceLocationFileIDMiddleIgnored() {
    let sourceLocation = SourceLocation(fileID: "A/B/C/D.swift", filePath: "", line: 1, column: 1)
    #expect(sourceLocation.moduleName == "A")
    #expect(sourceLocation.fileName == "D.swift")
  }

  @Test("SourceLocation.line and .column properties")
  func sourceLocationLineAndColumn() {
    var sourceLocation = #_sourceLocation
    #expect(sourceLocation.line > 0)
    #expect(sourceLocation.line < 500)
    #expect(sourceLocation.column > 0)
    #expect(sourceLocation.column < 80)

    sourceLocation.line = 12345
    #expect(sourceLocation.line == 12345)
    sourceLocation.column = 2468
    #expect(sourceLocation.column == 2468)
  }

#if !SWT_NO_EXIT_TESTS
  @Test("SourceLocation.init requires well-formed arguments")
  func sourceLocationInitPreconditions() async {
    await #expect(processExitsWith: .failure, "Empty fileID") {
      _ = SourceLocation(fileID: "", filePath: "", line: 1, column: 1)
    }
    await #expect(processExitsWith: .failure, "Invalid fileID") {
      _ = SourceLocation(fileID: "B.swift", filePath: "", line: 1, column: 1)
    }
    await #expect(processExitsWith: .failure, "Zero line") {
      _ = SourceLocation(fileID: "A/B.swift", filePath: "", line: 0, column: 1)
    }
    await #expect(processExitsWith: .failure, "Zero column") {
      _ = SourceLocation(fileID: "A/B.swift", filePath: "", line: 1, column: 0)
    }
  }

  @Test("SourceLocation.fileID property must be well-formed")
  func sourceLocationFileIDWellFormed() async {
    await #expect(processExitsWith: .failure) {
      var sourceLocation = #_sourceLocation
      sourceLocation.fileID = ""
    }
    await #expect(processExitsWith: .failure) {
      var sourceLocation = #_sourceLocation
      sourceLocation.fileID = "ABC"
    }
  }

  @Test("SourceLocation.line and column properties must be positive")
  func sourceLocationLineAndColumnPositive() async {
    await #expect(processExitsWith: .failure) {
      var sourceLocation = #_sourceLocation
      sourceLocation.line = -1
    }
    await #expect(processExitsWith: .failure) {
      var sourceLocation = #_sourceLocation
      sourceLocation.column = -1
    }
  }
#endif

  @Test("SourceLocation.filePath property")
  func sourceLocationFilePath() {
    var sourceLocation = #_sourceLocation
    #expect(sourceLocation.filePath == #filePath)

    sourceLocation.filePath = "A"
    #expect(sourceLocation.filePath == "A")
  }

  @available(swift, deprecated: 100000.0)
  @Test("SourceLocation._filePath property")
  func sourceLocation_FilePath() {
    var sourceLocation = #_sourceLocation
    #expect(sourceLocation._filePath == #filePath)

    sourceLocation._filePath = "A"
    #expect(sourceLocation._filePath == "A")
  }

  @Test("SourceLocation comparisons")
  func comparisons() {
    do {
      let loc1 = SourceLocation(fileID: "A/B", filePath: "", line: 1, column: 1)
      let loc2 = SourceLocation(fileID: "A/C", filePath: "", line: 1, column: 1)
      #expect(loc1 < loc2)
    }

    do {
      let loc1 = SourceLocation(fileID: "A/B", filePath: "", line: 1, column: 1)
      let loc2 = SourceLocation(fileID: "A/B", filePath: "", line: 2, column: 1)
      #expect(loc1 < loc2)
    }

    do {
      let loc1 = SourceLocation(fileID: "A/B", filePath: "", line: 1, column: 1)
      let loc2 = SourceLocation(fileID: "A/B", filePath: "", line: 1, column: 2)
      #expect(loc1 < loc2)
    }

    do {
      let loc1 = SourceLocation(fileID: "A/B", filePath: "", line: 1, column: 2)
      let loc2 = SourceLocation(fileID: "A/B", filePath: "", line: 2, column: 1)
      #expect(loc1 < loc2)
    }

    do {
      let loc1 = SourceLocation(fileID: "A/B", filePath: "", line: 2, column: 1)
      let loc2 = SourceLocation(fileID: "A/C", filePath: "", line: 1, column: 1)
      #expect(loc1 < loc2)
    }

    do {
      let loc1 = SourceLocation(fileID: "A/B", filePath: "", line: 1, column: 2)
      let loc2 = SourceLocation(fileID: "A/C", filePath: "", line: 1, column: 1)
      #expect(loc1 < loc2)
    }

    do {
      let loc1 = SourceLocation(fileID: "A/B", filePath: "A", line: 1, column: 1)
      let loc2 = SourceLocation(fileID: "A/B", filePath: "B", line: 1, column: 1)
      #expect(loc1 == loc2)
    }
  }

  @Test("Custom source location argument to #expect()")
  func customSourceLocationArgument() async {
    await confirmation("Source location matched custom") { sourceLocationMatched in
      let lineNumber = Int.random(in: 999_999 ..< 1_999_999)

      var configuration = Configuration()
      configuration.eventHandler = { event, _ in
        guard case let .issueRecorded(issue) = event.kind else {
          return
        }
        if issue.sourceLocation?.line == lineNumber {
          sourceLocationMatched()
        }
      }
      await Test {
        #expect(Bool(false), sourceLocation: SourceLocation(fileID: "A/B", filePath: "", line: lineNumber, column: 1))
      }.run(configuration: configuration)
    }
  }
}
