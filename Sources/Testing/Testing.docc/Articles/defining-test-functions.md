# Defining test functions

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Define a test function to validate that code is working correctly.

## Overview

Defining a test function for a Swift package or project is straightforward.

This article assumes that the package or project being tested has already been
configured with a test target. For help configuring a package to use the testing
library, see <doc:TemporaryGettingStarted>.

## Importing the testing library

To import the testing library, add the following to the Swift source file that
will contain the test:

```swift
import Testing
```

- Note: Only import the testing library into a test target. Importing the
  testing library into an application, library, or binary target is not
  supported or recommended. Test functions are not stripped from binaries when
  building for release, so logic and fixtures of a test may be visible to anyone
  who inspects a build product containing a test function.

## Declaring a test function

To declare a test function, write a Swift function declaration that does not
take any arguments, then prefix its name with the `@Test` attribute:

```swift
@Test func foodTruckExists() {
  // Test logic goes here.
}
```

This test function can be present at file scope or within a type. A type
containing test functions is automatically a _test suite_ and can be optionally
annotated with the `@Suite` attribute. For more information about suites, see
<doc:OrganizingTests>.

Note that, while this function is a valid test function, it does not actually
perform any action or test any code. To check for expected values and outcomes
in test functions, add [expectations](doc:Expectations) to the test function.

## Customizing a test's name

To customize a test function's name as presented in an IDE or at the command
line, supply a string literal as an argument to the `@Test` attribute:

```swift
@Test("Food truck exists") func foodTruckExists() { ... }
```

To further customize the appearance and behavior of a test function, use
 [traits](doc:Traits) such as ``Trait/tags(_:)-505n9``.

## Writing concurrent or throwing tests

As with other Swift functions, test functions can be marked `async` and `throws`
to annotate them as concurrent or throwing, respectively. If a test is only safe
to run in the main actor's execution context (that is, from the main thread of
the process), it can be annotated `@MainActor`:

```swift
@Test @MainActor func foodTruckExists() async throws { ... }
```

## Limiting the availability of a test

If a test function can only run on newer versions of an operating system or of
the Swift language, use the `@available` attribute when declaring it. Use the
`message` argument of the `@available` attribute to specify a message to log if
a test is unable to run due to limited availability:

```swift
@available(macOS 11.0, *)
@available(swift, introduced: 5.9, message: "Requires Swift 5.9 features to run")
@Test func foodTruckExists() { ... }
```

## Topics

- ``Test``
- ``Test(_:_:)``

## See Also

- <doc:Expectations>
- <doc:ParameterizedTesting>
