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

#if canImport(Foundation)
import Foundation
#endif

@Suite("Tag/Tag List Tests", .tags(.traitRelated))
struct TagListTests {
  @Test(".tags() factory method with one string")
  func tagListFactoryMethodWithOneString() throws {
    let trait = Tag.List.tags("hello")
    #expect((trait as Any) is Tag.List)
    #expect(trait.tags == [Tag("hello")])
  }

  @Test(".tags() factory method with two strings")
  func tagListFactoryMethodWithTwoStrings() throws {
    let trait = Tag.List.tags("hello", "world")
    #expect((trait as Any) is Tag.List)
    #expect(trait.tags == [Tag("hello"), Tag("world")])
  }

  @Test(".tags() factory method with colors", .tags(.red, .orange, .yellow, .green, .blue, .purple))
  func tagListFactoryMethodWithColors() throws {
    let trait = Tag.List.tags(.red, .orange, .yellow, .green, .blue, .purple)
    #expect((trait as Any) is Tag.List)
    #expect(trait.tags == [.red, .orange, .yellow, .green, .blue, .purple])
    #expect(trait.tags == [
      Tag(kind: .staticMember("red")),
      Tag(kind: .staticMember("orange")),
      Tag(kind: .staticMember("yellow")),
      Tag(kind: .staticMember("green")),
      Tag(kind: .staticMember("blue")),
      Tag(kind: .staticMember("purple"))
    ])
    #expect(trait.tags.allSatisfy { $0.isPredefinedColor })
  }

  @Test("Tag.description property", arguments: [
    Tag("hello"): #""hello""#,
    Tag("world"): #""world""#,
    .red: ".red",
    .orange: ".orange",
    .yellow: ".yellow",
    .green: ".green",
    .blue: ".blue",
    .purple: ".purple",
  ])
  func tagDescription(tag: Tag, expectedDescription: String) throws {
    #expect(String(describing: tag) == expectedDescription)
  }

  @Test("Tag.List.description property")
  func tagListDescription() throws {
    let trait = Tag.List.tags(Tag("hello"), Tag("world"), .red, .orange, .yellow, .green, .blue, .purple)
    #expect((trait as Any) is Tag.List)
    #expect(String(describing: trait) == "\"hello\", \"world\", .red, .orange, .yellow, .green, .blue, .purple")
  }

  @Test("Tag.List comparisons")
  func tagListComparison() throws {
    #expect(Tag("A") != Tag("B"))
    #expect(Tag("A") < Tag("B"))
    #expect(Tag("B") > Tag("A"))
    #expect(!(Tag("B") < Tag("A")))
    // Symbolic tags are compared alphabetically too, but sort before string
    // literal tags.
    #expect(Tag.orange < Tag.red)
    #expect(!(Tag.red < Tag.orange))
    #expect(Tag.red < Tag("A"))
    #expect(!(Tag("A") < Tag.red))
  }

  @Test("Test.tags property")
  func testTagsProperty() {
    let test = Test(.tags("A", "B")) {}
    #expect(test.tags == [Tag("A"), Tag("B")])
  }

  @Test("Tags are recursively applied")
  func tagsAreRecursivelyApplied() async throws {
    let plan = await Runner.Plan(selecting: TagTests.self)

    let typeTest = try #require(plan.steps.map(\.test).first { $0.name == "TagTests" })
    #expect(typeTest.tags == [Tag("FromType")])
    let functionTest = try #require(plan.steps.map(\.test).first { $0.name == "test()" })
    #expect(functionTest.tags == [Tag("FromFunction"), Tag("FromType")])

    let functionTest2 = try #require(plan.steps.map(\.test).first { $0.name == "variations()" })
    #expect(functionTest2.tags.contains(.NestedType.deeperTag))
    #expect(!functionTest2.tags.contains(.OtherNestedType.deeperTag))
  }

  @Test("Tags can be parsed from user-provided strings")
  func userProvidedStringValues() {
    #expect(Tag(userProvidedStringValue: "abc123") == Tag(kind: .stringLiteral("abc123")))
    #expect(Tag(userProvidedStringValue: ".red") == .red)
    #expect(Tag(userProvidedStringValue: #"\.abc123"#) == Tag(kind: .stringLiteral(#".abc123"#)))
    #expect(Tag(userProvidedStringValue: #"\\.abc123"#) == Tag(kind: .stringLiteral(#"\.abc123"#)))
  }

#if canImport(Foundation)
  @Test("Encoding/decoding tags")
  func encodeAndDecodeTags() throws {
    let array: [Tag] = [.red, .orange, Tag("abc123"), Tag(".abc123"), Tag(#"\.abc123"#), Tag(#"\\.abc123"#)]
    let data = try JSONEncoder().encode(array)
    let array2 = try JSONDecoder().decode([Tag].self, from: data)
    #expect(array == array2)
  }

  @Test("Tags as codable dictionary keys")
  func encodeAndDecodeTagsAsDictionaryKeys() throws {
    let dict: [Tag: Int] = [
      .red: 0,
      .orange: 1,
      Tag("abc123"): 2,
      Tag(".abc123"): 3,
      Tag(#"\.abc123"#): 4,
      Tag(#"\\.abc123"#): 4,
    ]
    let data = try JSONEncoder().encode(dict)
    let dict2 = try JSONDecoder().decode([Tag: Int].self, from: data)
    #expect(dict == dict2)
  }

#if !SWT_NO_FILE_IO
  @Test(
    "Colors are read from disk",
    .tags("alpha", "beta", "gamma", "delta"), .tags(.namedConstant)
  )
  func tagColorsReadFromDisk() throws {
    let tempDirURL = FileManager.default.temporaryDirectory
    let jsonURL = tempDirURL.appendingPathComponent("tag-colors.json", isDirectory: false)
    let jsonContent = """
    {
    "alpha": "red",
    "beta": "#00CCFF",
    "gamma": "#AABBCC",
    "delta": null,

    "encode red": "red",
    "encode orange": "orange",
    "encode yellow": "yellow",
    "encode green": "green",
    "encode blue": "blue",
    "encode purple": "purple"
    }
    """
    try jsonContent.write(to: jsonURL, atomically: true, encoding: .utf8)
    defer {
      try? FileManager.default.removeItem(at: jsonURL)
    }

    let tagColors = try Testing.loadTagColors(fromFileInDirectoryAtPath: tempDirURL.path)
    #expect(tagColors[Tag("alpha")] == .red)
    #expect(tagColors[Tag("beta")] == .rgb(0, 0xCC, 0xFF))
    #expect(tagColors[Tag("gamma")] == .rgb(0xAA, 0xBB, 0xCC))
    #expect(tagColors[Tag("delta")] == nil)

    #expect(tagColors[Tag("encode red")] == .red)
    #expect(tagColors[Tag("encode orange")] == .orange)
    #expect(tagColors[Tag("encode yellow")] == .yellow)
    #expect(tagColors[Tag("encode green")] == .green)
    #expect(tagColors[Tag("encode blue")] == .blue)
    #expect(tagColors[Tag("encode purple")] == .purple)
  }

  @Test("No colors are read from a bad path")
  func noTagColorsReadFromBadPath() throws {
    #expect(throws: (any Error).self) {
      try Testing.loadTagColors(fromFileInDirectoryAtPath: "Directory/That/Does/Not/Exist")
    }
  }

  @Test("Invalid tag color decoding", arguments: [##""#NOTHEX""##, #""garbageColorName""#])
  func noTagColorsReadFromBadPath(tagColorJSON: String) throws {
    let tagColorJSONData = try #require(tagColorJSON.data(using: .utf8))
    #expect(throws: (any Error).self) {
      _ = try JSONDecoder().decode(Tag.Color.self, from: tagColorJSONData)
    }
  }
#endif
#endif

  @Test("Tag colors are converted to 16-color correctly",
    arguments: [
      // Predefined colors (orange and purple are special-cased)
      (Tag.Color.red, 91), (.orange, 33), (.yellow, 93), (.green, 92), (.blue, 94), (.purple, 95),

      // Grays
      (.rgb(0, 0, 0), 30), (.rgb(255, 255, 255), 97), (.rgb(100, 100, 100), 90), (.rgb(200, 200, 200), 37),

      // Dark colors
      (.rgb(100, 0, 0), 31), (.rgb(100, 100, 0), 33), (.rgb(0, 100, 0), 32), (.rgb(0, 100, 100), 36), (.rgb(0, 0, 100), 34), (.rgb(100, 0, 100), 35),

      // Bright colors
      (.rgb(200, 0, 0), 91), (.rgb(200, 200, 0), 93), (.rgb(0, 200, 0), 92), (.rgb(0, 200, 200), 96), (.rgb(0, 0, 200), 94), (.rgb(200, 0, 200), 95),
    ]
  )
  func tagColorsTo16Color(tagColor: Tag.Color, ansiEscapeCodeValue: Int) {
    let ansiEscapeCode = tagColor.closest16ColorEscapeCode().dropFirst() // drop the \e
    #expect(ansiEscapeCode.contains("\(ansiEscapeCodeValue)m"))
  }

  @Test("Tag color sorting")
  func tagColorSorting() {
    // By hue
    #expect(Tag.Color.rgb(200, 0, 0) < .rgb(0, 0, 200))
    // By saturation
    #expect(Tag.Color.rgb(100, 50, 50) < .rgb(100, 0, 0))
    // By value
    #expect(Tag.Color.rgb(0, 0, 0) < .rgb(100, 100, 100))
  }

#if !SWT_NO_EXIT_TESTS && SWIFT_PM_SUPPORTS_SWIFT_TESTING
  @Test("Invalid symbolic tag declaration")
  func invalidSymbolicTag() async {
    await #expect(exitsWith: .failure) {
      _ = Tag.__fromStaticMember(of: String.self, "invalid")
    }
  }
#endif
}

// MARK: - Fixtures

extension Tag {
  @Tag static var namedConstant: Tag
  @Tag static var anotherConstant: Tag

  enum NestedType {
    @Tag static var deeperTag: Tag
  }

  enum OtherNestedType {
    @Tag static var deeperTag: Tag
  }
}

enum UnrelatedType {
  @Tag static var tagThatCannotBeUsed: Tag
}

@Suite(.hidden, .tags("FromType"))
struct TagTests {
  @Test(.hidden, .tags("FromFunction"))
  func test() async throws {}

  @Test(
    .hidden,
    Tag.List.tags("FromFunctionPartiallyQualified"),
    Testing.Tag.List.tags("FromFunctionFullyQualified"),
    .tags("Tag1", "Tag2"),
    .tags(.namedConstant, .NestedType.deeperTag, Testing.Tag.anotherConstant)
  )
  func variations() async throws {}
}
