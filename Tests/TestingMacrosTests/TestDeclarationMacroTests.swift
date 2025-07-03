//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

import Testing
@testable import TestingMacros

import SwiftBasicFormat
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@Suite("TestDeclarationMacro Tests")
struct TestDeclarationMacroTests {
  @Test("Error diagnostics emitted on API misuse",
    arguments: [
      // Generic declarations
      "@Suite struct S<T> {}":
        "Attribute 'Suite' cannot be applied to a generic structure",
      "@Suite struct S where X == Y {}":
        "Attribute 'Suite' cannot be applied to a generic structure",
      "@Test func f<T>() {}":
        "Attribute 'Test' cannot be applied to a generic function",
      "@Test func f() where X == Y {}":
        "Attribute 'Test' cannot be applied to a generic function",
      "@Test(arguments: []) func f(x: some T) {}":
        "Attribute 'Test' cannot be applied to a generic function",
      "@Test(arguments: []) func f(x: (some T)?) {}":
        "Attribute 'Test' cannot be applied to a generic function",

      // Multiple attributes on a declaration
      "@Suite @Suite struct S {}":
        "Attribute 'Suite' cannot be applied to a structure more than once",
      "@Suite @Suite final class C {}":
        "Attribute 'Suite' cannot be applied to a class more than once",
      "@Test @Test func f() {}":
        "Attribute 'Test' cannot be applied to a function more than once",

      // Attributes on unsupported declarations
      "@Test var x = 0":
        "Attribute 'Test' cannot be applied to a property",
      "@Test init() {}":
        "Attribute 'Test' cannot be applied to an initializer",
      "@Test deinit {}":
        "Attribute 'Test' cannot be applied to a deinitializer",
      "@Test subscript() -> Int {}":
        "Attribute 'Test' cannot be applied to a subscript",
      "@Test typealias X = Y":
        "Attribute 'Test' cannot be applied to a typealias",
      "enum E { @Test case c }":
        "Attribute 'Test' cannot be applied to an enumeration case",
      "@Suite func f() {}":
        "Attribute 'Suite' cannot be applied to a function",
      "@Suite extension X {}":
        "Attribute 'Suite' has no effect when applied to an extension",
      "@Test macro m()":
        "Attribute 'Test' cannot be applied to a macro",
      "@Test struct S {}":
        "Attribute 'Test' cannot be applied to a structure",
      "@Test enum E {}":
        "Attribute 'Test' cannot be applied to an enumeration",

      // Availability
      "@available(*, unavailable) @Suite struct S {}":
        "Attribute 'Suite' cannot be applied to this structure because it has been marked '@available(*, unavailable)'",
      "@available(*, noasync) @Suite enum E {}":
        "Attribute 'Suite' cannot be applied to this enumeration because it has been marked '@available(*, noasync)'",
      "@available(macOS 999.0, *) @Suite final class C {}":
        "Attribute 'Suite' cannot be applied to this class because it has been marked '@available(macOS 999.0, *)'",
      "@_unavailableFromAsync @Suite actor A {}":
        "Attribute 'Suite' cannot be applied to this actor because it has been marked '@_unavailableFromAsync'",

      // XCTestCase
      "@Suite final class C: XCTestCase {}":
        "Attribute 'Suite' cannot be applied to a subclass of 'XCTestCase'",
      "@Suite final class C: XCTest.XCTestCase {}":
        "Attribute 'Suite' cannot be applied to a subclass of 'XCTestCase'",
      "final class C: XCTestCase { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within class 'C'",
      "final class C: XCTest.XCTestCase { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within class 'C'",

      // Unsupported inheritance
      "@Suite protocol P {}":
        "Attribute 'Suite' cannot be applied to a protocol",

      // Invalid specifiers on arguments
      "@Test(arguments: [0]) func f(i: inout Int) {}":
        "Attribute 'Test' cannot be applied to a function with a parameter marked 'inout'",
      "@Test(arguments: [MyActor()]) func f(i: isolated MyActor) {}":
        "Attribute 'Test' cannot be applied to a function with a parameter marked 'isolated'",
      "@Test(arguments: [0.0]) func f(i: _const Double) {}":
        "Attribute 'Test' cannot be applied to a function with a parameter marked '_const'",

      // Argument count mismatches.
      "@Test(arguments: []) func f() {}":
        "Attribute 'Test' cannot specify arguments when used with function 'f()' because it does not take any",

      // Invalid lexical contexts
      "struct S { func f() { @Test func g() {} } }":
        "Attribute 'Test' cannot be applied to a function within function 'f()'",
      "struct S { func f(x: Int) { @Suite struct S { } } }":
        "Attribute 'Suite' cannot be applied to a structure within function 'f(x:)'",
      "struct S<T> { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within generic structure 'S'",
      "struct S<T> { @Suite struct S {} }":
        "Attribute 'Suite' cannot be applied to a structure within generic structure 'S'",
      "protocol P { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within protocol 'P'",
      "protocol P { @Suite struct S {} }":
        "Attribute 'Suite' cannot be applied to a structure within protocol 'P'",
      "{ _ in @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within a closure",
      "{ _ in @Suite struct S {} }":
        "Attribute 'Suite' cannot be applied to a structure within a closure",
      "@available(*, noasync) struct S { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to this function because it has been marked '@available(*, noasync)'",
      "@available(*, noasync) struct S { @Suite struct S {} }":
        "Attribute 'Suite' cannot be applied to this structure because it has been marked '@available(*, noasync)'",
      "extension [T] { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within a generic extension to type '[T]'",
      "extension [T] { @Suite struct S {} }":
        "Attribute 'Suite' cannot be applied to a structure within a generic extension to type '[T]'",
      "extension [T:U] { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within a generic extension to type '[T:U]'",
      "extension [T:U] { @Suite struct S {} }":
        "Attribute 'Suite' cannot be applied to a structure within a generic extension to type '[T:U]'",
      "extension T? { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within a generic extension to type 'T?'",
      "extension T? { @Suite struct S {} }":
        "Attribute 'Suite' cannot be applied to a structure within a generic extension to type 'T?'",
      "extension T! { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within a generic extension to type 'T!'",
      "extension T! { @Suite struct S {} }":
        "Attribute 'Suite' cannot be applied to a structure within a generic extension to type 'T!'",
      "struct S: ~Escapable { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within structure 'S' because its conformance to 'Escapable' has been suppressed",
      "struct S: ~Swift.Escapable { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within structure 'S' because its conformance to 'Escapable' has been suppressed",
      "struct S: ~(Escapable) { @Test func f() {} }":
        "Attribute 'Test' cannot be applied to a function within structure 'S' because its conformance to 'Escapable' has been suppressed",
    ]
  )
  func apiMisuseErrors(input: String, expectedMessage: String) throws {
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.count > 0)
    for diagnostic in diagnostics {
      #expect(diagnostic.diagMessage.severity == .error)
      #expect(diagnostic.message == expectedMessage)
    }
  }

  static var errorsWithFixIts: [String: (message: String, fixIts: [ExpectedFixIt])] {
    [
      // 'Test' attribute must specify arguments to parameterized test functions.
      "@Test func f(i: Int) {}":
        (
          message: "Attribute 'Test' must specify arguments when used with function 'f(i:)'",
          fixIts: [
            ExpectedFixIt(
              message: "Add 'arguments:' with one collection",
              changes: [.replace(oldSourceCode: "@Test ", newSourceCode: "@Test(arguments: \(EditorPlaceholderExprSyntax(type: "[Int]"))) ")]
            ),
          ]
        ),
      "@Test func f(i: Int, j: String) {}":
        (
          message: "Attribute 'Test' must specify arguments when used with function 'f(i:j:)'",
          fixIts: [
            ExpectedFixIt(
              message: "Add 'arguments:' with one collection",
              changes: [.replace(oldSourceCode: "@Test ", newSourceCode: "@Test(arguments: \(EditorPlaceholderExprSyntax(type: "[(Int, String)]"))) ")]
            ),
            ExpectedFixIt(
              message: "Add 'arguments:' with all combinations of 2 collections",
              changes: [.replace(oldSourceCode: "@Test ", newSourceCode: "@Test(arguments: \(EditorPlaceholderExprSyntax(type: "[Int]")), \(EditorPlaceholderExprSyntax(type: "[String]"))) ")]
            ),
          ]
        ),
      "@Test func f(i: Int, j: String, k: Double) {}":
        (
          message: "Attribute 'Test' must specify arguments when used with function 'f(i:j:k:)'",
          fixIts: [
            ExpectedFixIt(
              message: "Add 'arguments:' with one collection",
              changes: [.replace(oldSourceCode: "@Test ", newSourceCode: "@Test(arguments: \(EditorPlaceholderExprSyntax(type: "[(Int, String, Double)]"))) ")]
            ),
          ]
        ),
      #"@Test("Some display name") func f(i: Int) {}"#:
        (
          message: "Attribute 'Test' must specify arguments when used with function 'f(i:)'",
          fixIts: [
            ExpectedFixIt(
              message: "Add 'arguments:' with one collection",
              changes: [.replace(oldSourceCode: #"@Test("Some display name") "#, newSourceCode: #"@Test("Some display name", arguments: \#(EditorPlaceholderExprSyntax(type: "[Int]"))) "#)]
            ),
          ]
        ),
      #"@Test /*comment*/ func f(i: Int) {}"#:
        (
          message: "Attribute 'Test' must specify arguments when used with function 'f(i:)'",
          fixIts: [
            ExpectedFixIt(
              message: "Add 'arguments:' with one collection",
              changes: [.replace(oldSourceCode: #"@Test /*comment*/ "#, newSourceCode: #"@Test(arguments: \#(EditorPlaceholderExprSyntax(type: "[Int]"))) /*comment*/ "#)]
            ),
          ]
        ),

      #"@Test("Goodbye world") func `hello world`()"#:
        (
          message: "Attribute 'Test' specifies display name 'Goodbye world' for function with implicit display name 'hello world'",
          fixIts: [
            ExpectedFixIt(
              message: "Remove 'Goodbye world'",
              changes: [.replace(oldSourceCode: #""Goodbye world""#, newSourceCode: "")]
            ),
            ExpectedFixIt(
              message: "Rename 'hello world'",
              changes: [.replace(oldSourceCode: "`hello world`", newSourceCode: "\(EditorPlaceholderExprSyntax("name"))")]
            ),
          ]
        ),
    ]
  }

  @Test("Error diagnostics which include fix-its emitted on API misuse", arguments: errorsWithFixIts)
  func apiMisuseErrorsIncludingFixIts(input: String, expectedDiagnostic: (message: String, fixIts: [ExpectedFixIt])) throws {
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.count == 1)
    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.diagMessage.severity == .error)
    #expect(diagnostic.message == expectedDiagnostic.message)

    try #require(diagnostic.fixIts.count == expectedDiagnostic.fixIts.count)
    for (fixIt, expectedFixIt) in zip(diagnostic.fixIts, expectedDiagnostic.fixIts) {
      #expect(fixIt.message.message == expectedFixIt.message)

      try #require(fixIt.changes.count == expectedFixIt.changes.count)
      for (change, expectedChange) in zip(fixIt.changes, expectedFixIt.changes) {
        switch (change, expectedChange) {
        case let (.replace(oldNode, newNode), .replace(expectedOldSourceCode, expectedNewSourceCode)):
          let oldSourceCode = String(describing: oldNode.formatted())
          #expect(oldSourceCode == expectedOldSourceCode)

          let newSourceCode = String(describing: newNode.formatted())
          #expect(newSourceCode == expectedNewSourceCode)
        default:
          Issue.record("Change \(change) differs from expected change \(expectedChange)")
        }
      }
    }
  }

  @Test("Raw identifier is detected")
  func rawIdentifier() {
    #expect(TokenSyntax.identifier("`hello`").rawIdentifier == nil)
    #expect(TokenSyntax.identifier("`helloworld`").rawIdentifier == nil)
    #expect(TokenSyntax.identifier("`hélloworld`").rawIdentifier == nil)
    #expect(TokenSyntax.identifier("`hello_world`").rawIdentifier == nil)
    #expect(TokenSyntax.identifier("`hello world`").rawIdentifier != nil)
    #expect(TokenSyntax.identifier("`hello/world`").rawIdentifier != nil)
    #expect(TokenSyntax.identifier("`hello\tworld`").rawIdentifier != nil)

    #expect(TokenSyntax.identifier("`class`").rawIdentifier == nil)
    #expect(TokenSyntax.identifier("`struct`").rawIdentifier == nil)
    #expect(TokenSyntax.identifier("`class struct`").rawIdentifier != nil)
  }

  @Test("Raw function name components")
  func rawFunctionNameComponents() throws {
    let decl = """
    func `hello there`(`world of mine`: T, etc: U, `blah`: V) {}
    """ as DeclSyntax
    let functionDecl = try #require(decl.as(FunctionDeclSyntax.self))
    #expect(functionDecl.completeName.trimmedDescription == "`hello there`(`world of mine`:etc:blah:)")
  }

  @Test("Warning diagnostics emitted on API misuse",
    arguments: [
      // return types
      "@Test func f() -> Int {}":
        "The result of this function will be discarded during testing",
      "@Test func f() -> Swift.String {}":
        "The result of this function will be discarded during testing",
      "@Test func f() -> Int? {}":
        "The result of this function will be discarded during testing",
      "@Test func f() -> (Int, Int) {}":
        "The result of this function will be discarded during testing",

      // .serialized on a non-parameterized test function
      "@Test(.serialized) func f() {}":
        "Trait '.serialized' has no effect when used with a non-parameterized test function",
    ]
  )
  func apiMisuseWarnings(input: String, expectedMessage: String) throws {
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.count > 0)
    for diagnostic in diagnostics {
      #expect(diagnostic.diagMessage.severity == .warning)
      #expect(diagnostic.message == expectedMessage)
    }
  }

  @Test("Availability attributes are captured",
    arguments: [
      #"@available(moofOS 9, dogCow 30, *) @Test func f() {}"#:
        [
          #".__available("moofOS", introduced: (9, nil, nil), "#,
          #".__available("dogCow", introduced: (30, nil, nil), "#,
          #"guard #available (moofOS 9, *), #available (dogCow 30, *) else"#,
        ],
      #"@available(moofOS, introduced: 9) @available(dogCow, introduced: 30) @Test func f() {}"#:
        [
          #".__available("moofOS", introduced: (9, nil, nil), "#,
          #".__available("dogCow", introduced: (30, nil, nil), "#,
          #"guard #available (moofOS 9, *), #available (dogCow 30, *) else"#,
        ],
      #"@available(*, unavailable, message: "Clarus!") @Test func f() {}"#:
        [#".__unavailable(message: "Clarus!", "#],
      #"@available(moofOS, obsoleted: 9) @Test func f() {}"#:
        [#".__available("moofOS", obsoleted: (9, nil, nil), "#],
      #"@available(swift 1.0) @Test func f() {}"#:
        [
          #".__available("Swift", introduced: (1, 0, nil), "#,
          #"#if swift(>=1.0)"#,
        ],
      #"@available(swift, introduced: 1.0) @Test func f() {}"#:
        [
          #".__available("Swift", introduced: (1, 0, nil), "#,
          #"#if swift(>=1.0)"#,
        ],
      #"@available(swift, obsoleted: 2.0) @Test func f() {}"#:
        [
          #".__available("Swift", obsoleted: (2, 0, nil), "#,
          #"#if swift(<2.0)"#,
        ],
      #"@available(swift, introduced: 1.0, obsoleted: 2.0) @Test func f() {}"#:
        [
          #".__available("Swift", introduced: (1, 0, nil), "#,
          #".__available("Swift", obsoleted: (2, 0, nil), "#,
          #"#if swift(>=1.0) && swift(<2.0)"#,
        ],
      #"@available(moofOS, unavailable, message: "Moof!") @Test func f() {}"#:
        [
          #"#if os(moofOS)"#,
          #".__available("moofOS", obsoleted: nil, message: "Moof!", "#,
        ]
    ]
  )
  func availabilityAttributeCapture(input: String, expectedOutputs: [String]) throws {
    let (actualOutput, _) = try parse(input, removeWhitespace: true)

    for expectedOutput in expectedOutputs {
      let (expectedOutput, _) = try parse(expectedOutput, removeWhitespace: true)
      #expect(actualOutput.contains(expectedOutput))
    }
  }

  static var functionTypeInputs: [(String, String?, String?)] {
    var result: [(String, String?, String?)] = [
      ("@Test func f() {}", nil, nil),
      ("@Test @available(*, noasync) @MainActor func f() {}", nil, "MainActor.run"),
      ("@Test @_unavailableFromAsync @MainActor func f() {}", nil, "MainActor.run"),
      ("@Test @available(*, noasync) func f() {}", nil, "__requiringTry"),
      ("@Test @_unavailableFromAsync func f() {}", nil, "__requiringTry"),
      ("@Test(arguments: []) func f(f: () -> String) {}", "(() -> String).self", nil),
      ("struct S {\n\t@Test func testF() {} }", nil, "__invokeXCTestCaseMethod"),
      ("struct S {\n\t@Test func testF() throws {} }", nil, "__invokeXCTestCaseMethod"),
      ("struct S {\n\t@Test func testF() async {} }", nil, "__invokeXCTestCaseMethod"),
      ("struct S {\n\t@Test func testF() async throws {} }", nil, "__invokeXCTestCaseMethod"),
      (
        """
        struct S {
          #if SOME_CONDITION
          @OtherAttribute
          #endif
          @Test func testF() async throws {}
        }
        """,
        nil,
        nil
      ),
    ]

    result += [
      ("struct S_NAME {\n\t@Test func f() {} }", "S_NAME", "let"),
      ("struct S_NAME {\n\t@Test mutating func f() {} }", "S_NAME", "var"),
      ("struct S_NAME {\n\t@Test static func f() {} }", "S_NAME", nil),
      ("final class C_NAME {\n\t@Test class func f() {} }", "C_NAME", nil),
    ]

    return result
  }

  @Test("Different kinds of functions are handled correctly", arguments: functionTypeInputs)
  func differentFunctionTypes(input: String, expectedTypeName: String?, otherCode: String?) throws {
    let (output, _) = try parse(input)

#if hasFeature(SymbolLinkageMarkers)
    #expect(output.contains("@_section"))
#endif
#if !SWT_NO_LEGACY_TEST_DISCOVERY
    #expect(output.contains("__TestContentRecordContainer"))
#endif
    if let expectedTypeName {
      #expect(output.contains(expectedTypeName))
    }
    if let otherCode {
      #expect(output.contains(otherCode))
    }
  }

  @Test("Self. in @Test attribute is removed")
  func removeSelfKeyword() throws {
    let (output, _) = try parse("@Test(arguments: Self.nested.uniqueArgsName, NoTouching.thisOne) func f() {}")
    #expect(output.contains("nested.uniqueArgsName"))
    #expect(!output.contains("Self.nested.uniqueArgsName"))
    #expect(output.contains("NoTouching.thisOne"))
  }

  @Test("Display name is preserved",
    arguments: [
      #"@Test("Display Name") func f() {}"#,
      #"@Test("Display Name", .someTrait) func f() {}"#,
      #"@Test("Display Name", .someTrait, arguments: []) func f(i: Int) {}"#,
      #"@Test("Display Name", arguments: []) func f(i: Int) {}"#,
    ]
  )
  func preservesDisplayName(input: String) throws {
    let (output, _) = try parse(input)
    #expect(output.contains(": \"Display Name\""))
  }

  @Test("Nil display name")
  func nilDisplayName() throws {
    let input = #"@Test(nil, .someTrait) func f() {}"#
    let (output, _) = try parse(input)
    #expect(!output.contains("displayName:"))
  }

  @Test("Valid tag expressions are allowed",
    .tags(.traitRelated),
    arguments: [
      #"@Test(.tags(.f)) func f() {}"#,
      #"@Test(Tag.List.tags(.f)) func f() {}"#,
      #"@Test(Testing.Tag.List.tags(.f)) func f() {}"#,
      #"@Test(.tags("abc")) func f() {}"#,
      #"@Test(Tag.List.tags("abc")) func f() {}"#,
      #"@Test(Testing.Tag.List.tags("abc")) func f() {}"#,
      #"@Test(.tags(Tag.f)) func f() {}"#,
      #"@Test(.tags(Testing.Tag.f)) func f() {}"#,
      #"@Test(.tags(.Foo.Bar.f)) func f() {}"#,
      #"@Test(.tags(Testing.Tag.Foo.Bar.f)) func f() {}"#,
    ]
  )
  func validTagExpressions(input: String) throws {
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.isEmpty)
  }

  @Test("Invalid tag expressions are detected",
    .tags(.traitRelated),
    arguments: [
      "f()", ".f()", "loose",
      "WrongType.tag", "WrongType.f()",
      ".f.g(_:).h", ".f.g(123).h",
    ]
  )
  func invalidTagExpressions(tagExpr: String) throws {
    let input = "@Test(.tags(\(tagExpr))) func f() {}"
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.count > 0)
    for diagnostic in diagnostics {
      #expect(diagnostic.diagMessage.severity == .error)
      #expect(diagnostic.message == "Tag '\(tagExpr)' cannot be used with attribute 'Test'; pass a member of 'Tag' or a string literal instead")
    }
  }

  @Test("Valid bug identifiers are allowed",
    .tags(.traitRelated),
    arguments: [
      #"@Test(.bug(id: 12345)) func f() {}"#,
      #"@Test(.bug(id: "12345")) func f() {}"#,
      #"@Test(.bug("mailto:a@example.com")) func f() {}"#,
      #"@Test(.bug("rdar:12345")) func f() {}"#,
      #"@Test(.bug("rdar://12345")) func f() {}"#,
      #"@Test(.bug(id: "FB12345")) func f() {}"#,
      #"@Test(.bug("https://github.com/swiftlang/swift-testing/issues/12345")) func f() {}"#,
      #"@Test(.bug("https://github.com/swiftlang/swift-testing/issues/12345", id: "12345")) func f() {}"#,
      #"@Test(.bug("https://github.com/swiftlang/swift-testing/issues/12345", id: 12345)) func f() {}"#,
      #"@Test(Bug.bug("https://github.com/swiftlang/swift-testing/issues/12345")) func f() {}"#,
      #"@Test(Testing.Bug.bug("https://github.com/swiftlang/swift-testing/issues/12345")) func f() {}"#,
      #"@Test(Bug.bug("https://github.com/swiftlang/swift-testing/issues/12345", "here's what happened...")) func f() {}"#,
    ]
  )
  func validBugIdentifiers(input: String) throws {
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.isEmpty)
  }

  @Test("Invalid bug URLs are detected",
    .tags(.traitRelated),
    arguments: [
      "mailto: a@example.com", "example.com",
    ]
  )
  func invalidBugURLs(id: String) throws {
    let input = #"@Test(.bug("\#(id)")) func f() {}"#
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.count > 0)
    for diagnostic in diagnostics {
      #expect(diagnostic.diagMessage.severity == .warning)
      #expect(diagnostic.message == #"URL "\#(id)" is invalid and cannot be used with trait 'bug' in attribute 'Test'"#)
    }
  }
}
