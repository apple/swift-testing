# ``Testing``

<!-- NOTE: The link above must match the module name, not the package name. -->

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023–2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Create and run tests for your Swift packages and Xcode projects.

## Overview

With Swift Testing you leverage powerful and expressive capabilities of
the Swift programming language to develop tests with more confidence and less
code. The library integrates seamlessly with Swift Package Manager testing
workflow, supports flexible test organization, customizable metadata, and
scalable test execution. 

- Define test functions almost anywhere with a single attribute.
- Group related tests into hierarchies using Swift's type system.
- Integrate seamlessly with Swift concurrency.
- Parameterize test functions across wide ranges of inputs.
- Enable tests dynamically depending
on runtime conditions. 
- Parallelize tests in-process.
- Categorize tests using tags.
- Associate bugs directly with the tests that verify their fixes or reproduce
their problems.

#### Related videos

- [Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179)
- [Go further with Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10195)

## Topics

### Essentials

- <doc:DefiningTests>
- <doc:OrganizingTests>
- <doc:MigratingFromXCTest>
- ``Test(_:_:)``
- ``Test``
- ``Suite(_:_:)``

### Test parameterization

- <doc:ParameterizedTesting>
- ``Test(_:_:arguments:)-8kn7a``
- ``Test(_:_:arguments:_:)``
- ``Test(_:_:arguments:)-3rzok``
- ``CustomTestArgumentEncodable``
<!-- - ``Test/Parameter`` -->
- ``Test/Case``

### Behavior validation

- <doc:Expectations>
- <doc:known-issues>

### Test customization

- <doc:Traits>

### Data collection

- <doc:Attachments>
