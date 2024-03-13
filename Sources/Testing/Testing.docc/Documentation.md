# ``Testing``

<!-- NOTE: The link above must match the module name, not the package name. -->

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Create and run tests for your Swift packages and Xcode projects.

## Overview

`swift-testing` is a modern, open-source testing library for Swift with powerful
and expressive capabilities. It gives developers more confidence with less code.

### Flexible test organization

Define test functions almost anywhere with a single attribute and group related
tests into hierarchies using Swift's type system.

### Customizable metadata

Dynamically enable or disable tests depending on runtime conditions, categorize
tests using tags, and associate bugs directly with the tests that verify their
fixes or reproduce their problems.

### Scalable execution

Automatically parallelize tests in-process, integrate seamlessly with Swift
concurrency, and parameterize test functions across wide ranges of inputs.

## Topics

### Getting started

- <doc:TemporaryGettingStarted>

### Test definition

- <doc:defining-test-functions>
- ``Test``
- ``Test(_:_:)``

### Test organization

- <doc:organizing-test-functions-with-suite-types>
- ``Suite(_:_:)``

### Test parameterization

- <doc:running-a-test-function-multiple-times-with-different-input>
- ``Test(_:_:arguments:)-8kn7a``
- ``Test(_:_:arguments:_:)``
- ``Test(_:_:arguments:)-3rzok``
- ``CustomTestArgumentEncodable``
- ``Test/Parameter``
- ``Test/Case``

### Expected outcomes

- <doc:Expectations>

### Customizations

- <doc:Traits>

### Migration

- <doc:migrating-a-test-from-xctest>
