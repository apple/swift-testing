# Validating behavior using expectations

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Check for expected values and outcomes in tests.

## Overview

Tests may validate behaviors using expectations. This page describes the various
built-in expectation APIs.

## Topics

### Validating behavior using expectations

- ``expect(_:_:sourceLocation:)``
- ``require(_:_:sourceLocation:)-5l63q``
- ``require(_:_:sourceLocation:)-6w9oo``

### Validating asynchronous behavior using confirmations

- ``Confirmation``
- ``confirmation(_:expectedCount:fileID:filePath:line:column:_:)``

### Validating errors and issues in tests

- <doc:ExpectThrows>

### Retrieving information about checked expectations

- ``Expectation``
- ``ExpectationFailedError``
- ``CustomTestStringConvertible``
- ``Expression``

### Representing source locations

- ``SourceLocation``
- ``SourceContext``
- ``Backtrace``
