# Associating bugs with tests

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Associate bugs uncovered or verified by tests.

## Overview

Tests allow developers to prove that the code they write is working as expected.
If code is not working correctly, bug trackers are often used to track the work
necessary to fix the underlying problem. It is often useful to associate
specific bugs with tests that reproduce them or verify they are fixed.

- Note: "Bugs" as described in this document may also be referred to as
  "issues." To avoid confusion with the ``Issue`` type in the testing library,
  this document consistently refers to them as "bugs."

## Associating a bug with a test

To associate a bug with a test, use the ``Trait/bug(_:relationship:)-duvt``
or ``Trait/bug(_:relationship:)-40riy`` function. The first argument to this
function is the bug's _identifier_ in its bug-tracking system:

```swift
@Test("Food truck engine works", .bug("12345"), .bug(67890))
func engineWorks() async {
  var foodTruck = FoodTruck()
  await foodTruck.engine.start()
  #expect(foodTruck.engine.isRunning)
}
```

The bug identifier can be specified as an integer or as a string; if it is
specified as a string and matches certain formats, the testing library is able
to infer additional information about it. For more information on the formats
recognized by the testing library, see <doc:BugIdentifiers>.

## Specifying the relationship between a bug and a test

By default, the nature of the relationship between a bug and a test is
unspecified. All the testing library knows about such relationships is that they
exist.

It is possible to customize the relationship between a bug and a test. Doing so
allows the testing library to make certain assumptions, such as that a test is
expected to fail, or that a failure indicates a regression that requires
attention from a developer.

To specify how a bug is related to a test, use the `relationship` parameter of
the ``Trait/bug(_:relationship:)-duvt`` or ``Trait/bug(_:relationship:)-40riy``
function. For example, to indicate that a test was written to verify a
previously-fixed bug, one would specify `.verifiesFix`:

```swift
@Test("Food truck engine works", .bug("12345", relationship: .verifiesFix))
func engineWorks() async {
  var foodTruck = FoodTruck()
  await foodTruck.engine.start()
  #expect(foodTruck.engine.isRunning)
}
```

### Kinds of relationship

The testing library defines several kinds of common bug/test relationship:

| Relationship | Use when… |
|-|-|
| `.uncoveredBug` | … a test run failed, uncovering the bug in question. |
| `.reproducesBug` | … a bug was previously filed and the test was written to demonstrate it. |
| `.verifiesFix` | … a bug has been fixed and the test shows that it no longer reproduces. |
| `.failingBecauseOfBug` | … a test was previously passing, but now an unrelated bug is causing it to fail. |
| `.unspecified` | … no other case accurately describes the relationship. |

<!-- Keep `.unspecified` as the last row above in order to imply it is a
fallback. -->

## Topics

- <doc:BugIdentifiers>
- ``Trait/bug(_:relationship:)-duvt``
- ``Trait/bug(_:relationship:)-40riy``
- ``Bug``
