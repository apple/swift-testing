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

import SwiftDiagnostics
import SwiftOperators
import SwiftParser
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@Suite("ConditionMacro Tests")
struct ConditionMacroTests {
  @Test("#expect() macro",
    arguments: [
      ##"#expect(true)"##:
        ##"Testing.__checkValue(true, expression: .__fromSyntaxNode("true"), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(false)"##:
        ##"Testing.__checkValue(false, expression: .__fromSyntaxNode("false"), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(false, "Custom message")"##:
        ##"Testing.__checkValue(false, expression: .__fromSyntaxNode("false"), comments: ["Custom message"], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(2 > 1)"##:
        ##"Testing.__checkBinaryOperation(2, { $0 > $1() }, 1, expression: .__fromBinaryOperation(.__fromSyntaxNode("2"), ">", .__fromSyntaxNode("1")), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(((true || false) && true) || Bool.random())"##:
        ##"Testing.__checkBinaryOperation(((true || false) && true), { $0 || $1() }, Bool.random(), expression: .__fromBinaryOperation(.__fromSyntaxNode("((true || false) && true)"), "||", .__fromSyntaxNode("Bool.random()")), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(9 > 8 && 7 > 6, "Some comment")"##:
        ##"Testing.__checkBinaryOperation(9 > 8, { $0 && $1() }, 7 > 6, expression: .__fromBinaryOperation(.__fromSyntaxNode("9 > 8"), "&&", .__fromSyntaxNode("7 > 6")), comments: ["Some comment"], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect("a" == "b")"##:
        ##"Testing.__checkBinaryOperation("a", { $0 == $1() }, "b", expression: .__fromBinaryOperation(.__fromStringLiteral(#""a""#, "a"), "==", .__fromStringLiteral(#""b""#, "b")), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(!Bool.random())"##:
        ##"Testing.__checkFunctionCall(Bool.self, calling: { $0.random() }, expression: .__fromNegation(.__fromFunctionCall(.__fromSyntaxNode("Bool"), "random"), false), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect((true && false))"##:
        ##"Testing.__checkBinaryOperation(true, { $0 && $1() }, false, expression: .__fromBinaryOperation(.__fromSyntaxNode("true"), "&&", .__fromSyntaxNode("false")), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(try x())"##:
        ##"Testing.__checkValue(try x(), expression: .__fromSyntaxNode("try x()"), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(1 is Int)"##:
        ##"Testing.__checkCast(1, is: (Int).self, expression: .__fromBinaryOperation(.__fromSyntaxNode("1"), "is", .__fromSyntaxNode("Int")), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect("123") { 1 == 2 } then: { foo() }"##:
        ##"Testing.__checkClosureCall(performing: { 1 == 2 }, then: { foo() }, expression: .__fromSyntaxNode("1 == 2"), comments: ["123"], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect("123") { let x = 0 }"##:
        ##"Testing.__checkClosureCall(performing: { let x = 0 }, expression: .__fromSyntaxNode("let x = 0"), comments: ["123"], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect("123") { let x = 0; return x == 0 }"##:
        ##"Testing.__checkClosureCall(performing: { let x = 0; return x == 0 }, expression: .__fromSyntaxNode("{ let x = 0; return x == 0 }"), comments: ["123"], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a, "b", c: c)"##:
        ##"Testing.__checkValue(a, c: c, expression: .__fromSyntaxNode("a"), comments: ["b"], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a())"##:
        ##"Testing.__checkFunctionCall((), calling: { _ in a() }, expression: .__fromFunctionCall(nil, "a"), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(b(c))"##:
        ##"Testing.__checkFunctionCall((), calling: { b($1) }, c, expression: .__fromFunctionCall(nil, "b", (nil, .__fromSyntaxNode("c"))), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a.b(c))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0.b($1) }, c, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("c"))), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a.b(c, d: e))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0.b($1, d: $2) }, c, e, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("c")), ("d", .__fromSyntaxNode("e"))), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a.b(&c))"##:
        ##"Testing.__checkInoutFunctionCall(a.self, calling: { $0.b(&$1) }, &c, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("&c"))), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a.b(&c, &d))"##:
        ##"Testing.__checkValue(a.b(&c, &d), expression: .__fromSyntaxNode("a.b(&c, &d)"), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a.b(&c, d))"##:
        ##"Testing.__checkValue(a.b(&c, d), expression: .__fromSyntaxNode("a.b(&c, d)"), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a.b(try c()))"##:
        ##"Testing.__checkValue(a.b(try c()), expression: .__fromSyntaxNode("a.b(try c())"), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a?.b(c))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0?.b($1) }, c, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("c"))), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a???.b(c))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0???.b($1) }, c, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("c"))), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a?.b.c(d))"##:
        ##"Testing.__checkFunctionCall(a?.b.self, calling: { $0?.c($1) }, d, expression: .__fromFunctionCall(.__fromSyntaxNode("a?.b"), "c", (nil, .__fromSyntaxNode("d"))), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect({}())"##:
        ##"Testing.__checkValue({}(), expression: .__fromSyntaxNode("{}()"), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a.b(c: d))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0.b(c: $1) }, d, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", ("c", .__fromSyntaxNode("d"))), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a.b { c })"##:
        ##"Testing.__checkValue(a.b { c }, expression: .__fromSyntaxNode("a.b { c }"), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a, sourceLocation: someValue)"##:
        ##"Testing.__checkValue(a, expression: .__fromSyntaxNode("a"), comments: [], isRequired: false, sourceLocation: someValue).__expected()"##,
      ##"#expect(a.isB)"##:
        ##"Testing.__checkPropertyAccess(a.self, getting: { $0.isB }, expression: .__fromPropertyAccess(.__fromSyntaxNode("a"), .__fromSyntaxNode("isB")), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a???.isB)"##:
        ##"Testing.__checkPropertyAccess(a.self, getting: { $0???.isB }, expression: .__fromPropertyAccess(.__fromSyntaxNode("a"), .__fromSyntaxNode("isB")), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a?.b.isB)"##:
        ##"Testing.__checkPropertyAccess(a?.b.self, getting: { $0?.isB }, expression: .__fromPropertyAccess(.__fromSyntaxNode("a?.b"), .__fromSyntaxNode("isB")), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(a?.b().isB)"##:
        ##"Testing.__checkPropertyAccess(a?.b().self, getting: { $0?.isB }, expression: .__fromPropertyAccess(.__fromSyntaxNode("a?.b()"), .__fromSyntaxNode("isB")), comments: [], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
      ##"#expect(isolation: somewhere) {}"##:
        ##"Testing.__checkClosureCall(performing: {}, expression: .__fromSyntaxNode("{}"), comments: [], isRequired: false, isolation: somewhere, sourceLocation: Testing.SourceLocation.__here()).__expected()"##,
    ]
  )
  func expectMacro(input: String, expectedOutput: String) throws {
    let (expectedOutput, _) = try parse(expectedOutput, removeWhitespace: true)
    let (actualOutput, _) = try parse(input, removeWhitespace: true)
    #expect(expectedOutput == actualOutput)
  }

  @Test("#require() macro",
    arguments: [
      ##"#require(true)"##:
        ##"Testing.__checkValue(true, expression: .__fromSyntaxNode("true"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(false)"##:
        ##"Testing.__checkValue(false, expression: .__fromSyntaxNode("false"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(false, "Custom message")"##:
        ##"Testing.__checkValue(false, expression: .__fromSyntaxNode("false"), comments: ["Custom message"], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(2 > 1)"##:
        ##"Testing.__checkBinaryOperation(2, { $0 > $1() }, 1, expression: .__fromBinaryOperation(.__fromSyntaxNode("2"), ">", .__fromSyntaxNode("1")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(((true || false) && true) || Bool.random())"##:
        ##"Testing.__checkBinaryOperation(((true || false) && true), { $0 || $1() }, Bool.random(), expression: .__fromBinaryOperation(.__fromSyntaxNode("((true || false) && true)"), "||", .__fromSyntaxNode("Bool.random()")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(9 > 8 && 7 > 6, "Some comment")"##:
        ##"Testing.__checkBinaryOperation(9 > 8, { $0 && $1() }, 7 > 6, expression: .__fromBinaryOperation(.__fromSyntaxNode("9 > 8"), "&&", .__fromSyntaxNode("7 > 6")), comments: ["Some comment"], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require("a" == "b")"##:
        ##"Testing.__checkBinaryOperation("a", { $0 == $1() }, "b", expression: .__fromBinaryOperation(.__fromStringLiteral(#""a""#, "a"), "==", .__fromStringLiteral(#""b""#, "b")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(!Bool.random())"##:
        ##"Testing.__checkFunctionCall(Bool.self, calling: { $0.random() }, expression: .__fromNegation(.__fromFunctionCall(.__fromSyntaxNode("Bool"), "random"), false), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require((true && false))"##:
        ##"Testing.__checkBinaryOperation(true, { $0 && $1() }, false, expression: .__fromBinaryOperation(.__fromSyntaxNode("true"), "&&", .__fromSyntaxNode("false")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(try x())"##:
        ##"Testing.__checkValue(try x(), expression: .__fromSyntaxNode("try x()"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(1 is Int)"##:
        ##"Testing.__checkCast(1, is: (Int).self, expression: .__fromBinaryOperation(.__fromSyntaxNode("1"), "is", .__fromSyntaxNode("Int")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require("123") { 1 == 2 } then: { foo() }"##:
        ##"Testing.__checkClosureCall(performing: { 1 == 2 }, then: { foo() }, expression: .__fromSyntaxNode("1 == 2"), comments: ["123"], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require("123") { let x = 0 }"##:
        ##"Testing.__checkClosureCall(performing: { let x = 0 }, expression: .__fromSyntaxNode("let x = 0"), comments: ["123"], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require("123") { let x = 0; return x == 0 }"##:
        ##"Testing.__checkClosureCall(performing: { let x = 0; return x == 0 }, expression: .__fromSyntaxNode("{ let x = 0; return x == 0 }"), comments: ["123"], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a, "b", c: c)"##:
        ##"Testing.__checkValue(a, c: c, expression: .__fromSyntaxNode("a"), comments: ["b"], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a())"##:
        ##"Testing.__checkFunctionCall((), calling: { _ in a() }, expression: .__fromFunctionCall(nil, "a"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(b(c))"##:
        ##"Testing.__checkFunctionCall((), calling: { b($1) }, c, expression: .__fromFunctionCall(nil, "b", (nil, .__fromSyntaxNode("c"))), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a.b(c))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0.b($1) }, c, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("c"))), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a.b(c, d: e))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0.b($1, d: $2) }, c, e, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("c")), ("d", .__fromSyntaxNode("e"))), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a.b(&c))"##:
        ##"Testing.__checkInoutFunctionCall(a.self, calling: { $0.b(&$1) }, &c, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("&c"))), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a.b(&c, &d))"##:
        ##"Testing.__checkValue(a.b(&c, &d), expression: .__fromSyntaxNode("a.b(&c, &d)"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a.b(&c, d))"##:
        ##"Testing.__checkValue(a.b(&c, d), expression: .__fromSyntaxNode("a.b(&c, d)"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a.b(try c()))"##:
        ##"Testing.__checkValue(a.b(try c()), expression: .__fromSyntaxNode("a.b(try c())"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a?.b(c))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0?.b($1) }, c, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("c"))), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a???.b(c))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0???.b($1) }, c, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", (nil, .__fromSyntaxNode("c"))), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a?.b.c(d))"##:
        ##"Testing.__checkFunctionCall(a?.b.self, calling: { $0?.c($1) }, d, expression: .__fromFunctionCall(.__fromSyntaxNode("a?.b"), "c", (nil, .__fromSyntaxNode("d"))), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require({}())"##:
        ##"Testing.__checkValue({}(), expression: .__fromSyntaxNode("{}()"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a.b(c: d))"##:
        ##"Testing.__checkFunctionCall(a.self, calling: { $0.b(c: $1) }, d, expression: .__fromFunctionCall(.__fromSyntaxNode("a"), "b", ("c", .__fromSyntaxNode("d"))), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a.b { c })"##:
        ##"Testing.__checkValue(a.b { c }, expression: .__fromSyntaxNode("a.b { c }"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a, sourceLocation: someValue)"##:
        ##"Testing.__checkValue(a, expression: .__fromSyntaxNode("a"), comments: [], isRequired: true, sourceLocation: someValue).__required()"##,
      ##"#require(a.isB)"##:
        ##"Testing.__checkPropertyAccess(a.self, getting: { $0.isB }, expression: .__fromPropertyAccess(.__fromSyntaxNode("a"), .__fromSyntaxNode("isB")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a???.isB)"##:
        ##"Testing.__checkPropertyAccess(a.self, getting: { $0???.isB }, expression: .__fromPropertyAccess(.__fromSyntaxNode("a"), .__fromSyntaxNode("isB")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a?.b.isB)"##:
        ##"Testing.__checkPropertyAccess(a?.b.self, getting: { $0?.isB }, expression: .__fromPropertyAccess(.__fromSyntaxNode("a?.b"), .__fromSyntaxNode("isB")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(a?.b().isB)"##:
        ##"Testing.__checkPropertyAccess(a?.b().self, getting: { $0?.isB }, expression: .__fromPropertyAccess(.__fromSyntaxNode("a?.b()"), .__fromSyntaxNode("isB")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(isolation: somewhere) {}"##:
        ##"Testing.__checkClosureCall(performing: {}, expression: .__fromSyntaxNode("{}"), comments: [], isRequired: true, isolation: somewhere, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
    ]
  )
  func requireMacro(input: String, expectedOutput: String) throws {
    let (expectedOutput, _) = try parse(expectedOutput, removeWhitespace: true)
    let (actualOutput, _) = try parse(input, removeWhitespace: true)
    #expect(expectedOutput == actualOutput)
  }

  @Test("Unwrapping #require() macro",
    arguments: [
      ##"#require(Optional<Int>.none)"##:
        ##"Testing.__checkPropertyAccess(Optional<Int>.self, getting: { $0.none }, expression: .__fromPropertyAccess(.__fromSyntaxNode("Optional<Int>"), .__fromSyntaxNode("none")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(nil ?? 123)"##:
        ##"Testing.__checkBinaryOperation(nil, { $0 ?? $1() }, 123, expression: .__fromBinaryOperation(.__fromSyntaxNode("nil"), "??", .__fromSyntaxNode("123")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(123 ?? nil)"##:
        ##"Testing.__checkBinaryOperation(123, { $0 ?? $1() }, nil, expression: .__fromBinaryOperation(.__fromSyntaxNode("123"), "??", .__fromSyntaxNode("nil")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(123 as? Double)"##:
        ##"Testing.__checkCast(123,as: (Double).self, expression: .__fromBinaryOperation(.__fromSyntaxNode("123"), "as?", .__fromSyntaxNode("Double")), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(123 as Double)"##:
        ##"Testing.__checkValue(123 as Double, expression: .__fromSyntaxNode("123 as Double"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
      ##"#require(123 as! Double)"##:
        ##"Testing.__checkValue(123 as! Double, expression: .__fromSyntaxNode("123 as! Double"), comments: [], isRequired: true, sourceLocation: Testing.SourceLocation.__here()).__required()"##,
    ]
  )
  func unwrappingRequireMacro(input: String, expectedOutput: String) throws {
    let (expectedOutput, _) = try parse(expectedOutput)
    let (actualOutput, _) = try parse(input)
    #expect(expectedOutput == actualOutput)
  }

  @Test("Capturing comments above #expect()/#require()",
    arguments: [
      """
      // Source comment
      /** Doc comment */
      #expect(try x(), "Argument comment")
      """:
      """
      // Source comment
      /** Doc comment */
      Testing.__checkValue(try x(), expression: .__fromSyntaxNode("try x()"), comments: [.__line("// Source comment"),.__documentationBlock("/** Doc comment */"),"Argument comment"], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()
      """,

      """
      // Ignore me

      // Capture me
      #expect(try x())
      """:
      """
      // Ignore me

      // Capture me
      Testing.__checkValue(try x(), expression: .__fromSyntaxNode("try x()"), comments: [.__line("// Capture me")], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()
      """,

      """
      // Ignore me
      \t
      // Capture me
      #expect(try x())
      """:
      """
      // Ignore me
      \t
      // Capture me
      Testing.__checkValue(try x(), expression: .__fromSyntaxNode("try x()"), comments: [.__line("// Capture me")], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()
      """,

      """
      // Capture me
      try #expect(x)
      """:
      """
      // Capture me
      try Testing.__checkValue(x, expression: .__fromSyntaxNode("x"), comments: [.__line("// Capture me")], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()
      """,

      """
      // Capture me
      await #expect(x)
      """:
      """
      // Capture me
      await Testing.__checkValue(x, expression: .__fromSyntaxNode("x"), comments: [.__line("// Capture me")], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()
      """,

      """
      // Ignore me

      // Comment for try
      try
      // Comment for await
      await
      // Comment for expect
      #expect(x)
      """:
      """
      // Comment for try
      try
      // Comment for await
      await
      // Comment for expect
      Testing.__checkValue(x, expression: .__fromSyntaxNode("x"), comments: [.__line("// Comment for try"), .__line("// Comment for await"), .__line("// Comment for expect")], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()
      """,

      """
      // Ignore me
      func example() {
        // Capture me
        #expect(x())
      }
      """:
      """
      func example() {
        // Capture me
        Testing.__checkFunctionCall((), calling: { _ in
          x()
        }, expression: .__fromFunctionCall(nil, "x"), comments: [.__line("// Capture me")], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()
      }
      """,
    ]
  )
  func commentCapture(input: String, expectedOutput: String) throws {
    let (expectedOutput, _) = try parse(expectedOutput)
    let (actualOutput, _) = try parse(input)
    #expect(expectedOutput == actualOutput)
  }

  @Test("#expect(false) and #require(false) warn they always fail",
    arguments: ["#expect(false)", "#require(false)","#expect(!true)","#require(!true)"]
  )
  func expectAndRequireMacroWarnsForFailure(input: String) throws {
    let (_, diagnostics) = try parse(input)
    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.diagMessage.severity == .warning)
    #expect(diagnostic.message.contains("will always fail"))
  }

  @Test("#expect(true) and #require(true) note they always pass",
    arguments: ["#expect(true)", "#require(true)","#expect(!false)","#require(!false)"]
  )
  func expectAndRequireMacroWarnsForPassing(input: String) throws {
    let (_, diagnostics) = try parse(input)
    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.diagMessage.severity == .note)
    #expect(diagnostic.message.contains("will always pass"))
  }

  @Test("Bool(false) suppresses the warning about always failing",
    arguments: ["#expect(Bool(false))", "#require(Bool(false))","#expect(Bool(!true))","#require(Bool(!true))"]
  )
  func expectAndRequireMacroWarningSuppressedWithExplicitBoolInitializer(input: String) throws {
    let (_, diagnostics) = try parse(input)
    #expect(diagnostics.count == 0)
  }

  @Test("as! warns when used with #require()",
    arguments: ["#expect(x as! T)", "#require(x as! T)",]
  )
  func asExclamationMarkWarnsWithRequire(input: String) throws {
    let (_, diagnostics) = try parse(input)
    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.diagMessage.severity == .warning)
    #expect(diagnostic.message.contains("will be evaluated before"))
  }

  @Test("as! warning is suppressed for explicit Bool and Optional casts",
    arguments: [
      "#expect(x as! Bool)", "#require(x as! Bool)",
      "#expect(x as! T?)", "#require(x as! T?)",
      "#expect(x as! T!)", "#require(x as! T!)",
      "#expect(x as! Optional<T>)", "#require(x as! Optional<T>)",
      "#expect(x as! Swift.Optional<T>)", "#require(x as! Swift.Optional<T>)",
    ]
  )
  func asExclamationMarkSuppressedForBoolAndOptional(input: String) throws {
    let (_, diagnostics) = try parse(input)
    #expect(diagnostics.count == 0)
  }

  @Test("#require(Bool?) produces a diagnostic",
    arguments: [
      "#requireAmbiguous(expression)",
      "#requireAmbiguous((expression))",
      "#requireAmbiguous(a + b)",
      "#requireAmbiguous((a + b))",
      "#requireAmbiguous((a) + (b))",
    ]
  )
  func requireOptionalBoolProducesDiagnostic(input: String) throws {
    let (_, diagnostics) = try parse(input)

    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.diagMessage.severity == .warning)
    #expect(diagnostic.message.contains("is ambiguous"))
    #expect(diagnostic.fixIts.count == 2)
    #expect(diagnostic.fixIts[0].message.message.contains("as Bool?"))
    #expect(diagnostic.fixIts[1].message.message.contains("?? false"))
  }

  @Test("#require(as Bool?) suppresses its diagnostic",
    arguments: [
      "#requireAmbiguous(expression as Bool?)",
      "#requireAmbiguous((expression as Bool?))",
      "#requireAmbiguous((expression) as Bool?)",
      "#requireAmbiguous(a + b as Bool?)",
      "#requireAmbiguous((a + b) as Bool?)",
      "#requireAmbiguous((a) + (b) as Bool?)",
      "#requireAmbiguous(((a) + (b)) as Bool?)",
    ]
  )
  func requireOptionalBoolSuppressedWithExplicitType(input: String) throws {
    // Note we do not need to test "as Bool" (non-optional) because an
    // expression of type Bool rather than Bool? won't trigger the additional
    // diagnostics in the first place.
    let (_, diagnostics) = try parse(input)
    #expect(diagnostics.isEmpty)
  }

  @Test("#require(non-optional value) produces a diagnostic",
    arguments: [
      "#requireNonOptional(expression)",
    ]
  )
  func requireNonOptionalProducesDiagnostic(input: String) throws {
    let (_, diagnostics) = try parse(input)

    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.diagMessage.severity == .warning)
    #expect(diagnostic.message.contains("is redundant"))
  }

#if !SWT_FIXED_137943258
  @Test(
    "#require(optional value mistyped as non-optional) diagnostic is suppressed",
    .bug("https://github.com/swiftlang/swift/issues/79202"),
    arguments: [
      "#requireNonOptional(expression as? T)",
      "#requireNonOptional(expression as Optional<T>)",
      "#requireNonOptional(expression ?? nil)",
    ]
  )
  func requireNonOptionalDiagnosticSuppressed(input: String) throws {
    let (_, diagnostics) = try parse(input)
    #expect(diagnostics.isEmpty)
  }
#endif

  @Test("#require(throws: Never.self) produces a diagnostic",
    arguments: [
      "#requireThrows(throws: Swift.Never.self)",
      "#requireThrows(throws: Never.self)",
      "#requireThrowsNever(throws: Never.self)",
    ]
  )
  func requireThrowsNeverProducesDiagnostic(input: String) throws {
    let (_, diagnostics) = try parse(input)

    let diagnostic = try #require(diagnostics.first)
    #expect(diagnostic.diagMessage.severity == .warning)
    #expect(diagnostic.message.contains("is redundant"))
  }

  @Test("#expect(processExitsWith:) diagnostics",
    arguments: [
      "func f<T>() { #expectExitTest(processExitsWith: x) {} }":
        "Cannot call macro ''#expectExitTest(processExitsWith:_:)'' within generic function 'f()'",
    ]
  )
  func exitTestDiagnostics(input: String, expectedMessage: String) throws {
    let (_, diagnostics) = try parse(input)

    #expect(diagnostics.count > 0)
    for diagnostic in diagnostics {
      #expect(diagnostic.diagMessage.severity == .error)
      #expect(diagnostic.message == expectedMessage)
    }
  }

#if ExperimentalExitTestValueCapture
  @Test("#expect(processExitsWith:) produces a diagnostic for a bad capture",
        arguments: [
          "#expectExitTest(processExitsWith: x) { [weak a] in }":
            "Specifier 'weak' cannot be used with captured value 'a'",
          "#expectExitTest(processExitsWith: x) { [a] in }":
            "Type of captured value 'a' is ambiguous",
          "#expectExitTest(processExitsWith: x) { [a = b] in }":
            "Type of captured value 'a' is ambiguous",
          "#expectExitTest(processExitsWith: x) { [a = b as any T] in }":
            "Type of captured value 'a' is ambiguous",
          "#expectExitTest(processExitsWith: x) { [a = b as some T] in }":
            "Type of captured value 'a' is ambiguous",
          "struct S<T> { func f() { #expectExitTest(processExitsWith: x) { [a] in } } }":
            "Cannot call macro ''#expectExitTest(processExitsWith:_:)'' within generic structure 'S'",
        ]
  )
  func exitTestCaptureDiagnostics(input: String, expectedMessage: String) throws {
    try ExitTestExpectMacro.$isValueCapturingEnabled.withValue(true) {
      let (_, diagnostics) = try parse(input)

      #expect(diagnostics.count > 0)
      for diagnostic in diagnostics {
        #expect(diagnostic.diagMessage.severity == .error)
        #expect(diagnostic.message == expectedMessage)
      }
    }
  }
#endif

  @Test(
    "Capture list on an exit test produces a diagnostic",
    arguments: [
      "#expectExitTest(processExitsWith: x) { [a] in }":
        "Cannot specify a capture clause in closure passed to '#expectExitTest(processExitsWith:_:)'"
    ]
  )
  func exitTestCaptureListProducesDiagnostic(input: String, expectedMessage: String) throws {
    try ExitTestExpectMacro.$isValueCapturingEnabled.withValue(false) {
      let (_, diagnostics) = try parse(input)

      #expect(diagnostics.count > 0)
      for diagnostic in diagnostics {
        #expect(diagnostic.diagMessage.severity == .error)
        #expect(diagnostic.message == expectedMessage)
      }
    }
  }

  @Test("Macro expansion is performed within a test function")
  func macroExpansionInTestFunction() throws {
    let input = ##"""
      @Test("Random number generation") func rng() {
        let number = Int.random(in: 1 ..< .max)
        #expect((number > 0 && foo() != bar(at: 9)) != !true, "\(number) must be greater than 0")
      }
    """##

    let rawExpectedOutput = ##"""
      @Test("Random number generation") func rng() {
        let number = Int.random(in: 1 ..< .max)
        Testing.__checkBinaryOperation((number > 0 && foo() != bar(at: 9)), { $0 != $1() }, !true, expression: .__fromBinaryOperation(.__fromSyntaxNode("(number > 0 && foo() != bar(at: 9))"), "!=", .__fromSyntaxNode("!true")), comments: ["\(number) must be greater than 0"], isRequired: false, sourceLocation: Testing.SourceLocation.__here()).__expected()
      }
    """##

    let (expectedOutput, _) = try parse(rawExpectedOutput, activeMacros: ["expect"], removeWhitespace: true)
    let (actualOutput, _) = try parse(input, activeMacros: ["expect"], removeWhitespace: true)
    #expect(expectedOutput == actualOutput)
  }
}
