# Enabling and disabling tests

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Conditionally enable or disable individual tests before they run.

## Overview

Often, a test will only be applicable in specific circumstances. For instance,
you might want to write a test that only runs on devices with particular
hardware capabilities, or performs locale-dependent operations. The testing
library allows you to add traits to your tests that cause runners to
automatically skip them if conditions like these are not met.

- Note: A condition may be evaluated multiple times during testing.

## Disabling a test

If a test should be disabled unconditionally, you can use the
``Trait/disabled(_:fileID:filePath:line:column:)`` function. Given the following
test function:

```swift
@Test("Food truck sells burritos")
func sellsBurritos() async throws { ... }
```

Add the trait _after_ the test's display name:

```swift
@Test("Food truck sells burritos", .disabled())
func sellsBurritos() async throws { ... }
```

The test will now always be skipped.

It is also possible to add a comment to the trait that will be presented in the
output from the runner when it skips the test:

```swift
@Test("Food truck sells burritos", .disabled("We only sell Thai cuisine"))
func sellsBurritos() async throws { ... }
```

## Conditionally enabling or disabling a test

Sometimes, it makes sense to enable a test only if a condition is met. Consider
the following test function:

```swift
@Test("Ice cream is cold")
func isCold() async throws { ... }
```

If it is currently winter, then presumably ice cream will not be available for
sale and this test will fail. It therefore makes sense to only enable it if it
is currently summer. You can conditionally enable a test with
``Trait/enabled(if:_:fileID:filePath:line:column:)``:

```swift
@Test("Ice cream is cold", .enabled(if: Season.current == .summer))
func isCold() async throws { ... }
```

It is also possible to conditionally _disable_ a test and to combine multiple
conditions:

```swift
@Test(
  "Ice cream is cold",
  .enabled(if: Season.current == .summer),
  .disabled("We ran out of sprinkles")
)
func isCold() async throws { ... }
```

If a test is disabled because of a problem for which there is a corresponding
bug report, you can use the ``Trait/bug(_:relationship:)-duvt`` or
``Trait/bug(_:relationship:)-40riy`` function with the relationship
``Bug/Relationship-swift.enum/failingBecauseOfBug``:

```swift
@Test(
  "Ice cream is cold",
  .enabled(if: Season.current == .summer),
  .disabled("We ran out of sprinkles"),
  .bug("#12345", relationship: .failingBecauseOfBug)
)
func isCold() async throws { ... }
```

If a test has multiple conditions applied to it, they must _all_ pass for it to
run. Otherwise, the first condition to fail will be noted as the reason the test
was skipped.

## Handling complex conditions

If a condition is complex, consider factoring it out into a helper function to
improve readability:

```swift
func allIngredientsAvailable(for food: Food) -> Bool { ... }

@Test(
  "Can make sundaes",
  .enabled(if: Season.current == .summer),
  .enabled(if: allIngredientsAvailable(for: .sundae))
)
func makeSundae() async throws { ... }
```

## Topics

- ``Trait/enabled(if:_:fileID:filePath:line:column:)``
- ``Trait/enabled(_:fileID:filePath:line:column:_:)``
- ``Trait/disabled(_:fileID:filePath:line:column:)``
- ``Trait/disabled(if:_:fileID:filePath:line:column:)``
- ``Trait/disabled(_:fileID:filePath:line:column:_:)``
- ``ConditionTrait``
