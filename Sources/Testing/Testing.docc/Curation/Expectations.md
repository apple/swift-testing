# Expectations and confirmations

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Check for expected values and outcomes in tests.

## Overview

The testing library provides `#expect()` and `#require()` macros you use to 
validate expected outcomes and a `Confirmation` type you can use to confirm the 
occurance of asyncronous events. To validate that an error is thrown, or _not_ thrown, 
the testing library provides several overloads of the macros that you can use.

## Topics

### Checking expected outcomes

- ``expect(_:_:sourceLocation:)``
- ``require(_:_:sourceLocation:)-5l63q``
- ``require(_:_:sourceLocation:)-6w9oo``

### Confirming asynchronous events

- ``confirmation(_:expectedCount:fileID:filePath:line:column:_:)``
- ``Confirmation``

### Checking for expected errors

- ``expect(throws:_:sourceLocation:performing:)-79piu``
- ``expect(throws:_:sourceLocation:performing:)-1xr34``
- ``expect(_:sourceLocation:performing:throws:)``
- ``require(throws:_:sourceLocation:performing:)-76bjn``
- ``require(throws:_:sourceLocation:performing:)-7v83e``
- ``require(_:sourceLocation:performing:throws:)``

### Checking for unexpected errors

- ``expect(throws:_:sourceLocation:performing:)-5lzjz``
- ``require(throws:_:sourceLocation:performing:)-36uzc``

### Retrieving information about checked expectations

- ``Expectation``
- ``ExpectationFailedError``
- ``CustomTestStringConvertible``
- ``Expression``

### Representing source locations

- ``SourceLocation``
- ``SourceContext``
- ``Backtrace``

