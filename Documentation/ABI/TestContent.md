# Runtime-discoverable test content

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

This document describes the format and location of test content that the testing
library emits at compile time and can discover at runtime.

## Basic format

Swift Testing stores test content records in a dedicated platform-specific
section in built test products:

| Platform | Binary Format | Section Name |
|-|:-:|-|
| macOS, iOS, watchOS, tvOS, visionOS | Mach-O | `__DATA_CONST,__swift5_tests` |
| Linux, FreeBSD, OpenBSD, Android | ELF | `swift5_tests` |
| WASI | WebAssembly | `swift5_tests` |
| Windows | PE/COFF | `.sw5test$B`[^windowsPadding] |

[^windowsPadding]: On Windows, the Swift compiler [emits](https://github.com/swiftlang/swift/blob/main/stdlib/public/runtime/SwiftRT-COFF.cpp)
  leading and trailing padding into this section, both zeroed and of size
  `MemoryLayout<UInt>.stride`. Code that walks this section must skip over this
  padding. This padding will be removed in a future update to the Swift
  toolchain ([swift-#87650](https://github.com/swiftlang/swift/issues/87650)).

In Embedded Swift, or when statically linking the standard library and runtime,
there is a single statically linked test content section. At
this time, statically-linked test content is supported if you use the Mach-O,
ELF, or Wasm image format.

### Record layout

Regardless of platform, all test content records created and discoverable by the
testing library have the following layout:

```swift
typealias Accessor = @convention(c) (
  _ outValue: UnsafeMutableRawPointer,
  _ type: UnsafeRawPointer,
  _ hint: UnsafeRawPointer?,
  _ reserved: UInt
) -> CBool

typealias TestContentRecord = (
  kind: UInt32,
  reserved1: UInt32,
  accessor: Accessor?,
  context: UInt,
  reserved2: UInt
)
```

This type has natural size, stride, and alignment. Its fields are native-endian.
If needed, this type can be represented in C as a structure:

```c
typedef bool (* SWTAccessor)(
  void *outValue,
  const void *type,
  const void *_Nullable hint,
  uintptr_t reserved
);

struct SWTTestContentRecord {
  uint32_t kind;
  uint32_t reserved1;
  SWTAccessor _Nullable accessor;
  uintptr_t context;
  uintptr_t reserved2;
};
```

Do not use the `__TestContentRecord` or `__TestContentRecordAccessor` typealias
defined in the testing library. These types exist to support the testing
library's macros and may change in the future (e.g. to accomodate a generic
argument or to make use of a reserved field.)

Instead, define your own copy of these types where needed&mdash;you can copy the
definitions above _verbatim_. If your test record type's `context` field (as
described below) is a pointer type, make sure to change its type in your version
of `TestContentRecord` accordingly so that, on systems with pointer
authentication enabled, the pointer is correctly resigned at load time.

### Record content

#### The kind field

Each record's _kind_ determines how the record will be interpreted at runtime. A
record's kind is a 32-bit unsigned value. The following kinds are defined:

| As Hexadecimal | As [FourCC](https://en.wikipedia.org/wiki/FourCC) | Interpretation |
|-:|:-:|-|
| `0x00000000` | &ndash; | Reserved (**do not use**) |
| `0x74657374` | `'test'` | Test or suite declaration |
| `0x65786974` | `'exit'` | Exit test |
| `0x706c6179` | `'play'` | [Playground](https://github.com/apple/swift-play-experimental) |

<!-- The kind values listed in this table should be a superset of the constants
in Sources/_TestDiscovery/TestContentKind.swift. -->

If a test content record's `kind` field equals `0x00000000`, the values of all
other fields in that record are undefined.

#### The accessor field

The function `accessor` is a C function. When called, it initializes the memory
at `outValue` to an instance of the appropriate type and returns `true`; or, if
it could not generate the relevant content, it leaves the memory uninitialized
and returns `false`. On successful return, the caller is responsible for
deinitializing the memory at `outValue` when done with it.

If `accessor` is `nil`, the test content record is ignored. The testing library
may, in the future, define record kinds that do not provide an accessor function
(that is, they represent pure compile-time information only.)

The second argument to this function, `type`, is a pointer to the type[^mightNotBeSwift]
(not a bitcast Swift type) of the value expected to be written to `outValue`.
This argument helps to prevent memory corruption if two copies of Swift Testing
or a third-party library are inadvertently loaded into the same process. If the
value at `type` does not match the test content record's expected type, the
accessor function must return `false` and must not modify `outValue`.

[^mightNotBeSwift]: Although this document primarily deals with Swift, the test
  content record section is generally language-agnostic. The use of languages
  other than Swift is beyond the scope of this document. With that in mind, it
  is _technically_ feasible for a test content accessor to be written in (for
  example) C++, expect the `type` argument to point to a C++ value of type
  [`std::type_info`](https://en.cppreference.com/w/cpp/types/type_info), and
  write a C++ class instance to `outValue` using [placement `new`](https://en.cppreference.com/w/cpp/language/new#Placement_new).

The third argument to this function, `hint`, is an optional input that can be
passed to help the accessor function determine if its corresponding test content
record matches what the caller is looking for. If the caller passes `nil` as the
`hint` argument, the accessor behaves as if it matched (that is, no additional
filtering is performed.)

The fourth argument to this function, `reserved`, is reserved for future use.
Accessor functions should assume it is `0` and must not access it.

The concrete Swift type of the value written to `outValue`, the type pointed to
by `type`, and the value pointed to by `hint` depend on the kind of record.

The record kinds defined by Swift Testing (kinds `0x74657374` and `0x65786974`)
make use of the `DiscoverableAsTestContent` protocol in the `_TestDiscovery`
module and do not publicly expose the types of their accessor functions'
arguments. Do not call the accessor functions for these records directly.

> [!WARNING]
> Calling code should use [`withUnsafeTemporaryAllocation(of:capacity:_:)`](https://developer.apple.com/documentation/swift/withunsafetemporaryallocation(of:capacity:_:))
> and/or [`withUnsafePointer(to:_:)`](https://developer.apple.com/documentation/swift/withunsafepointer(to:_:)-35wrn)
> to ensure the pointers passed to `accessor` are large enough and are
> well-aligned. If they are not large enough to contain values of the
> appropriate types (per above), or if `type` or `hint` points to uninitialized
> or incorrectly-typed memory, the result is undefined.

#### The context field

This field can be used by test content to store additional context for a test
content record that needs to be made available before the accessor is called:

- For test or suite declarations (kind `0x74657374`), this field contains a bit
  mask with the following flags currently defined:

  | Bit | Value | Description |
  |-:|-:|-|
  | `1 << 0` | `1` | This record contains a suite declaration |
  | `1 << 1` | `2` | This record contains a parameterized test function declaration |

  Other bits are reserved for future use and must be set to `0`.

- For exit test declarations (kind `0x65786974`), this field is reserved for
  future use and must be set to `0`.

#### The reserved1 and reserved2 fields

These fields are reserved for future use. Always set them to `0`.

## Third-party test content

Testing tools may make use of the same storage and discovery mechanisms by
emitting their own test content records into the test record content section.

Third-party test content should set the `kind` field to a unique value only used
by that tool, or used by that tool in collaboration with other compatible tools.
At runtime, Swift Testing ignores test content records with unrecognized `kind`
values. To reserve a new unique `kind` value, open a [GitHub issue](https://github.com/swiftlang/swift-testing/issues/new/choose)
against Swift Testing. The value you reserve does not need to be representable
as a [FourCC](https://en.wikipedia.org/wiki/FourCC) value, but it can be helpful
for debugging purposes.

The layout of third-party test content records must be compatible with that of
`TestContentRecord` as specified above. Third-party tools are ultimately
responsible for ensuring the values they emit into the test content section are
correctly aligned and have sufficient padding; failure to do so may render
downstream test code unusable.

<!--
TODO: elaborate further, give examples
TODO: standardize a mechanism for third parties to produce `Test` instances
      since we don't have a public initializer for the `Test` type.
-->

## Discovering previously-emitted test content

<!--
TODO: add more detail here about how to set up a package 
-->

To add test content discovery support to your package, add a dependency on the
`_TestDiscovery` module in the `swift-testing` package (not the copy of Swift
Testing included with the Swift toolchain or Xcode), then import the module with
SPI enabled:

```swift
@_spi(Experimental) @_spi(ForToolsIntegrationOnly) import _TestDiscovery
```

> [!IMPORTANT]
> Don't add a dependency on the `swift-testing` package's `Testing` module. If
> you add a dependency on this module, it will cause you to build and link Swift
> Testing every time you build your package. You only need the `_TestDiscovery`
> module in order to discover your own test content types.

After importing `_TestDiscovery`, find the type in your module that should be
discoverable at runtime and add conformance to the `DiscoverableAsTestContent`
protocol:

```swift
extension FoodTruckDiagnostic: DiscoverableAsTestContent {
  static var testContentKind: TestContentKind { /* Your `kind` value here. */ }
}
```

This type does not need to be publicly visible. However, if the values produced
by your accessor functions are members of a public type, you may be able to
simplify your code by using the same type.

If you have defined a custom `context` type other than `UInt`, you can specify
it here by setting the associated `TestContentContext` type. If you have defined
a custom `hint` type for your accessor functions, you can set
`TestContentAccessorHint`:

```swift
extension FoodTruckDiagnostic: DiscoverableAsTestContent {
  static var testContentKind: TestContentKind { /* Your `kind` value here. */ }
  
  typealias TestContentContext = UnsafePointer<FoodTruck.Name>
  typealias TestContentAccessorHint = String
}
```

If you customize `TestContentContext`, be aware that the type you specify must
have the same stride as `UInt` and must have an alignment less than or equal to
that of `UInt`.

When you are done configuring your type's protocol conformance, you can then
enumerate all test content records matching it as instances of
`TestContentRecord`.

You can use the `context` property to access the `context` field of the record
(as emitted into the test content section). The testing library will
automatically cast the value of the field to an instance of `TestContentContext`
for you.

If you find a record you wish to resolve to an instance of your conforming type,
call its `load()` function. `load()` calls the record's accessor function and,
if you have set a hint type, lets you pass an optional instance of that type: 

```swift
for diagnosticRecord in FoodTruckDiagnostic.allTestContentRecords() {
  if diagnosticRecord.context.pointee == .briansBranMuffins {
    if let diagnostic = diagnosticRecord.load(withHint: "...") {
      diagnostic.run()
    }
  }
}
```
