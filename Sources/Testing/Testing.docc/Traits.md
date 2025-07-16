# Traits

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2023–2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Annotate test functions and suites, and customize their behavior.

## Overview

Pass built-in traits to test functions or suite types to comment, categorize, 
classify, and modify the runtime behavior of test suites and test functions.
Implement the ``TestTrait``, and ``SuiteTrait`` protocols to create your own
types that customize the behavior of your tests.

## Topics

### Customizing runtime behaviors

- <doc:EnablingAndDisabling>
- <doc:LimitingExecutionTime>
- ``Trait/enabled(if:_:sourceLocation:)``
- ``Trait/enabled(_:sourceLocation:_:)``
- ``Trait/disabled(_:sourceLocation:)``
- ``Trait/disabled(if:_:sourceLocation:)``
- ``Trait/disabled(_:sourceLocation:_:)``
- ``Trait/timeLimit(_:)-4kzjp``

### Running tests serially or in parallel

- <doc:Parallelization>
- ``Trait/serialized``

### Annotating tests

- <doc:AddingTags>
- <doc:AddingComments>
- <doc:AssociatingBugs>
- <doc:BugIdentifiers>
- ``Tag()``
- ``Trait/bug(_:_:)``
- ``Trait/bug(_:id:_:)-10yf5``
- ``Trait/bug(_:id:_:)-3vtpl``

### Handling issues

- ``Trait/compactMapIssues(_:)``
- ``Trait/filterIssues(_:)``

### Creating custom traits

- ``Trait``
- ``TestTrait``
- ``SuiteTrait``
- ``TestScoping``

### Supporting types

- ``Bug``
- ``Comment``
- ``ConditionTrait``
- ``IssueHandlingTrait``
- ``ParallelizationTrait``
- ``Tag``
- ``Tag/List``
- ``TimeLimitTrait``
