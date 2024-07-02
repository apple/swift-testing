# JSON schema

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

This document outlines the JSON schemas used by the testing library for its ABI
entry point and for the `--event-stream-output` command-line argument. For more
information about the ABI entry point, see the documentation for
[ABIv0.EntryPoint](https://github.com/search?q=repo%3Aapple%2Fswift-testing%EntryPoint&type=code).

## Modified Backus-Naur form

This schema is expressed using a modified Backus-Naur syntax. `{`, `}`, `:`, and
`,` represent their corresponding JSON tokens. `\n` represents an ASCII newline
character.

The order of keys in JSON objects is not normative. Whitespace in this schema is
not normative; it is present to help the reader understand the content of the
various JSON objects in the schema. The event stream is output using the JSON
Lines format and does not include newline characters (except **one** at the end
of the `<output-record-line>` rule.)

Trailing commas in JSON objects and arrays are only to be included where
syntactically valid.

### Common data types

`<string>` and `<number>` are defined as in JSON. `<array:T>` represents an
array (also defined as in JSON) whose elements all follow rule `<T>`.

```
<bool> ::= true | false ; as in JSON

<source-location> ::= {
  "fileID": <string>, ; the Swift file ID of the file
  "line": <number>,
  "column": <number>,
}

<instant> ::= {
  "absolute": <number>, ; floating-point seconds since system-defined epoch
  "since1970": <number>, ; floating-point seconds since 1970-01-01 00:00:00 UT
}

<version> ::= "version": 0 ; will be incremented as the format changes
```

<!--
TODO: implement input/configuration

### Configuration

A single configuration is passed into the testing library prior to running any
tests and, as the name suggests, configures the test run. The configuration is
encoded as a single [JSON Lines](https://jsonlines.org) value.

```
<configuration-record> ::= {
  <version>,
  "kind": "configuration",
  "payload": <configuration>
}

<configuration> ::= {
  ["verbosity": <number>,] ; 0 is the default; higher means more verbose output
                           ; while negative values mean quieter output.
  ["filters": <array:test-filter>,] ; how to filter the tests in the test run
  ["parallel": <bool>,] ; whether to enable parallel testing (on by default)
  ; more TBD
}

<test-filter> ::= <test-filter-tag> | <test-filter-id>

<test-filter-action> ::= "include" | "exclude"

<test-filter-tag> ::= {
  "action": <test-filter-action>,
  "tags": <array:string>, ; the names of tags to include
  "operator": <test-filter-tag-operator> ; how to combine the values in "tags"
}

<test-filter-tag-operator> ::= "any" | "all"

<test-filter-id> ::= {
  "action": <test-filter-action>,
  "id": <test-id> ; the ID of the test to filter in/out
}
```
-->

### Streams

A stream consists of a sequence of values encoded as [JSON Lines](https://jsonlines.org).
A single instance of `<output-stream>` is defined per test process and can be
accessed by passing `--event-stream-output` to the test executable created by
`swift build --build-tests`.

```
<output-stream> ::= <output-record>\n | <output-record>\n <output-stream>
```

### Records

Records represent the values produced on a stream. Each record is encoded on a
single line and can be decoded independently of other lines. If a decoder
encounters a record whose `"kind"` field is unrecognized, the decoder should
ignore that line.

```
<output-record> ::= <test-record> | <event-record>

<test-record> ::= {
  <version>,
  "kind": "test",
  "payload": <test>
}

<event-record> ::= {
  <version>,
  "kind": "event",
  "payload": <event>
}
```

### Tests

Test records represent individual test functions and test suites. Test records
are passed through the record stream **before** most events.

<!--
If a test record represents a parameterized test function whose inputs are
enumerable and can be independently replayed, the test record will include an
additional `"testCases"` field describing the individual test cases.
-->

```
<test> ::= <test-suite> | <test-function>

<test-suite> ::= {
  "kind": "suite",
  "name": <string>, ; the unformatted, unqualified type name
  ["displayName": <string>,] ; the user-supplied custom display name
  "sourceLocation": <source-location>, ; where the test suite is defined
  "id": <test-id>,
}

<test-function> ::= {
  "kind": "function",
  "name": <string>, ; the unformatted function name
  ["displayName": <string>,] ; the user-supplied custom display name
  "sourceLocation": <source-location>, ; where the test is defined
  "id": <test-id>,
  "isParameterized": <bool> ; is this a parameterized test function or not?
}

<test-id> ::= <string> ; an opaque string representing the test case
```

<!--
  TODO: define a round-trippable format for a test case ID
  ["testCases": <array:test-case>] ; if "isParameterized": true and the inputs
                                   ; are enumerable, all test case IDs,
                                   ; otherwise not present

<test-case> ::= {
  "id": <string>, ; an opaque string representing the test case
  "displayName": <string> ; a string representing the corresponding Swift value
}
```
-->

### Events

Event records represent things that can happen during testing. They include
information about the event such as when it occurred and where in the test
source it occurred. They also include a `"messages"` field that contains
sufficient information to display the event in a human-readable format.

```
<event> ::= {
  "kind": <event-kind>,
  "instant": <instant>, ; when the event occurred
  ["issue": <issue>,] ; the recorded issue (if "kind" is "issueRecorded")
  "messages": <array:message>,
  ["testID": <test-id>,]
}

<event-kind> ::= "runStarted" | "testStarted" | "testCaseStarted" |
  "issueRecorded" | "testCaseEnded" | "testEnded" | "testSkipped" |
  "runEnded" ; additional event kinds may be added in the future

<issue> ::= {
  "isKnown": <bool>, ; is this a known issue or not?
  ["sourceLocation": <source-location>,] ; where the issue occurred, if known
}

<message> ::= {
  "symbol": <message-symbol>,
  "text": <string>, ; the human-readable text of this message
}

<message-symbol> ::= "default" | "skip" | "pass" | "passWithKnownIssue" |
  "fail" | "difference" | "warning" | "details"
```

<!--
  ["testID": <test-id>,
    ["testCase": <test-case>]]
-->
