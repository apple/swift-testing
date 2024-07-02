//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if SWT_NO_LIBRARY_MACRO_PLUGINS
import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The main entry point for the compiler plugin executable that implements
/// macros declared in the `Testing` module.
@main
struct TestingMacrosMain: CompilerPlugin {
  var providingMacros: [any Macro.Type] {
    [
      SuiteDeclarationMacro.self,
      TestDeclarationMacro.self,
      ExpectMacro.self,
      RequireMacro.self,
      AmbiguousRequireMacro.self,
      ExitTestExpectMacro.self,
      ExitTestRequireMacro.self,
      TagMacro.self,
      SourceLocationMacro.self,
    ]
  }
}
#endif
