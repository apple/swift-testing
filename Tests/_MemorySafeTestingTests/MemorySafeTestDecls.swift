//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if compiler(>=6.2)

@testable import Testing

#if !hasFeature(StrictMemorySafety)
#error("This file requires strict memory safety to be enabled")
#endif

@Test(.hidden)
func exampleTestFunction() {}

@Suite(.hidden)
struct ExampleSuite {
  @Test func example() {}
}

#if !SWT_NO_EXIT_TESTS
func exampleExitTest() async {
  await #expect(processExitsWith: .success) {}
}
#endif

#endif
