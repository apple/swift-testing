//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable @_spi(ExperimentalEventHandling) @_spi(ExperimentalTestRunning) import Testing

@Suite("Runner.Context Tests")
struct Runner_ContextTests {
  // This confirms that the `eventHandler` of a nested runner's configuration
  // has the context of the "outer" runner, so that task local data is handled
  // appropriately.
  @Test func contextScopedEventHandler() async {
    var configuration = Configuration()
    configuration.eventHandler = { _, _ in
      // Inside this event handler, the current Test should be the outer `@Test`
      // function, not the temporary `Test` created below.
      #expect(Test.current?.name == "contextScopedEventHandler()")
    }

    await Test(name: "foo") {}.run(configuration: configuration)
  }
}
