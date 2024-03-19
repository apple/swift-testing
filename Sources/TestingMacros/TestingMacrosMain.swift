//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(SwiftCompilerPlugin)
import SwiftCompilerPlugin
#if swift(>=5.11)
import SwiftSyntaxMacros
#else
public import SwiftSyntaxMacros
#endif

/// The main entry point for the compiler plugin executable that provides macros
/// for the `swift-testing` package.
@main
struct TestingMacrosMain: CompilerPlugin {
  var providingMacros: [any Macro.Type] {
    [
      SuiteDeclarationMacro.self,
      TestDeclarationMacro.self,
      ExpectMacro.self,
      RequireMacro.self,
      AmbiguousRequireMacro.self,
      TagMacro.self,
      CurrentSourceLocationMacro.self,
    ]
  }
}
#endif
