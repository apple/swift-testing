# Porting to new platforms

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2024 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

When the Swift toolchain is ported to a new platform, it is necessary to port
Swift Testing as well. This document contains various information, trivia, and
deep wisdoms about porting Swift Testing.

> [!NOTE]
> This document uses Classic Mac OS ("Classic") as an example target platform.
> In this hypothetical scenario, we assume that the Swift compiler identifies
> Classic with `os(Classic)` and that the C++ compiler identifies it with
> `defined(macintosh)`. Other platforms would be identified differently.

## Getting started

Before you start the porting process, make sure you are very familiar with Swift
and C++ as well as the C standard library and platform SDK for your target
platform.

Your first task when porting Swift Testing is ensuring that it builds.

We've made an effort to ensure that as much of our code as possible is
platform-agnostic. When building the toolchain for a new platform, you will
hopefully find that Swift Testing builds out-of-the-box with few, if any,
errors.

> [!NOTE]
> Swift Testing relies on the Swift [standard library](https://github.com/swiftlang/swift),
> Swift macros (including the [swift-syntax](https://github.com/swiftlang/swift-syntax) package),
> and [Foundation](https://github.com/apple/swift-foundation). These components
> must build and (minimally) function before you will be able to successfully
> build Swift Testing regardless of which platform you are porting to.

### Swift or C++?

Generally, prefer to implement changes in Swift rather than C++ where possible.
Swift Testing is a Swift package and our goal is to keep as much of it written
in Swift as we can. Generally speaking, you should not need to write much code
using C++.

## Resolving "platform-specific implementation missing" warnings

The package will _not_ build without warnings which you (or we) will need
to resolve. These warnings take the form:

> ⚠️ WARNING: Platform-specific implementation missing: ...

These warnings may be emitted by our internal C++ module (`_TestingInternals`)
or by our library module (`Testing`). Both indicate areas of our code that need
platform-specific attention.

> [!NOTE]
> Rarely, you may encounter errors of a similar form:
> 
> > 🛑 ERROR: Platform-specific misconfiguration: ...
> 
> These errors are produced when the configuration you're trying to build has
> conflicting requirements (for example, attempting to enable support for pipes
> without also enabling support for file I/O.) You should be able to resolve
> these issues by updating `Package.swift` and/or `CompilerSettings.cmake`.
>
> Don't forget to add your platform to the `BuildSettingCondition/whenApple(_:)`
> function in `Package.swift`.

Most platform dependencies can be resolved through the use of platform-specific
API. For example, Swift Testing uses the C11 standard [`timespec`](https://en.cppreference.com/w/c/chrono/timespec)
type to accurately track the durations of test runs. If you are porting Swift
Testing to Classic, you will run into trouble getting the UTC time needed by
`Test.Clock`, but you could use the platform-specific [`GetDateTime()`](https://developer.apple.com/library/archive/documentation/mac/pdf/Operating_System_Utilities/DT_And_M_Utilities.pdf)
function to get the current system time.

### Including system headers

Before we can call `GetDateTime()` from Swift, we need the Swift compiler to be
able to see it. Swift Testing includes an internal clang module,
`_TestingInternals`, that includes any system-provided C headers that we use as
well as a small amount of C++ glue code (for code that cannot currently be
implemented directly in Swift.) `GetDateTime()` is declared in `DateTimeUtils.h`
on Classic, so we would add that header to `Includes.h` in the internal target:

```diff
--- a/Sources/_TestingInternals/include/Includes.h
+++ b/Sources/_TestingInternals/include/Includes.h

+#if defined(macintosh)
+#include <DateTimeUtils.h>
+#endif
```

We intentionally don't import platform-specific C standard library modules
(`Darwin`, `Glibc`, `WinSDK`, etc.) in Swift because they often include overlay
code written in Swift and adding those modules as dependencies would make it
more difficult to test that Swift code using Swift Testing. 

### Changes in Swift

Once the header is included, we can call `GetDateTime()` from `Clock.swift`:

```diff
--- a/Sources/Testing/Events/Clock.swift
+++ b/Sources/Testing/Events/Clock.swift

 fileprivate(set) var wall: TimeValue = {
 #if !SWT_NO_TIMESPEC
   // ...
+#elseif os(Classic)
+  var seconds = CUnsignedLong(0)
+  GetDateTime(&seconds)
+  seconds -= 2_082_844_800 // seconds between epochs
+  return TimeValue((seconds: Int64(seconds), attoseconds: 0))
 #else
 #warning("Platform-specific implementation missing: UTC time unavailable (no timespec)")
 #endif
 }
```

## Runtime test discovery

When porting to a new platform, you may need to provide a new implementation for
`_sectionBounds(_:)` in `Discovery+Platform.swift`. Test discovery is dependent
on Swift metadata discovery which is an inherently platform-specific operation.

_Most_ platforms in use today use the ELF image format and will be able to reuse
the implementation used by Linux.

Classic does not use the ELF image format, so you'll need to write a custom
implementation of `_sectionBounds(_:)` instead. Assuming that the Swift compiler
emits section information into the resource fork on Classic, you would use the
[Resource Manager](https://developer.apple.com/library/archive/documentation/mac/pdf/MoreMacintoshToolbox.pdf)
to load that information:

```diff
--- a/Sources/_TestDiscovery/SectionBounds.swift
+++ b/Sources/_TestDiscovery/SectionBounds.swift

 // ...
+#elseif os(Classic)
+private func _sectionBounds(_ kind: SectionBounds.Kind) -> [SectionBounds] {
+  let resourceName: Str255 = switch kind {
+  case .testContent:
+    "__swift5_tests"
+#if !SWT_NO_LEGACY_TEST_DISCOVERY
+  case .typeMetadata:
+    "__swift5_types"
+#endif
+  }
+
+  let oldRefNum = CurResFile()
+  defer {
+    UseResFile(oldRefNum)
+  }
+
+  var refNum = ResFileRefNum(0)
+  guard noErr == GetTopResourceFile(&refNum) else {
+    return []
+  }
+
+  var result = [SectionBounds]()
+  repeat {
+    UseResFile(refNum)
+    guard let handle = Get1NamedResource(ResType("swft"), resourceName) else {
+      continue
+    }
+    let sb = SectionBounds(
+      imageAddress: UnsafeRawPointer(bitPattern: UInt(refNum)),
+      buffer: UnsafeRawBufferPointer(
+        start: handle.pointee,
+        count: GetHandleSize(handle)
+      )
+    )
+    result.append(sb)
+  } while noErr == GetNextResourceFile(refNum, &refNum))
+  return result
+}
+
 #elseif !SWT_NO_DYNAMIC_LINKING
 // MARK: - Missing dynamic implementation

 private func _sectionBounds(_ kind: SectionBounds.Kind) -> EmptyCollection<SectionBounds> {
 #warning("Platform-specific implementation missing: Runtime test discovery unavailable (dynamic)")
   return EmptyCollection()
 }
 #endif
```

You will also need to update the `makeTestContentRecordDecl()` function in the
`TestingMacros` target to emit the correct `@_section` attribute for your
platform. If your platform uses the ELF image format and supports the
`dl_iterate_phdr()` function, add it to the existing `#elseif os(Linux) || ...`
case. Otherwise, add a new case for your platform:

```diff
--- a/Sources/TestingMacros/Support/TestContentGeneration.swift
+++ b/Sources/TestingMacros/Support/TestContentGeneration.swift
   // ...
+  #elseif os(Classic)
+  @_section(".rsrc,swft,__swift5_tests")
   #else
   @__testing(warning: "Platform-specific implementation missing: test content section name unavailable")
   #endif
```

Keep in mind that this code is emitted by the `@Test` and `@Suite` macros
directly into test authors' test targets, so you will not be able to use
compiler conditionals defined in the Swift Testing package (including those that
start with `"SWT_"`).

## Runtime test discovery with static linkage

If your platform does not support dynamic linking and loading, you will need to
use static linkage instead. Define the `"SWT_NO_DYNAMIC_LINKING"` compiler
conditional for your platform in both `Package.swift` and
`CompilerSettings.cmake`, then define the symbols `_testContentSectionBegin`,
`_testContentSectionEnd`, `_typeMetadataSectionBegin`, and
`_typeMetadataSectionEnd` in `SectionBounds.swift`:

```diff
--- a/Sources/_TestDiscovery/SectionBounds.swift
+++ b/Sources/_TestDiscovery/SectionBounds.swift
 // ...
+#elseif os(Classic)
+@_silgen_name(raw: "...") private nonisolated(unsafe) var _testContentSectionBegin: _SectionBound
+@_silgen_name(raw: "...") private nonisolated(unsafe) var _testContentSectionEnd: _SectionBound
+#if !SWT_NO_LEGACY_TEST_DISCOVERY
+@_silgen_name(raw: "...") private nonisolated(unsafe) var _typeMetadataSectionBegin: _SectionBound
+@_silgen_name(raw: "...") private nonisolated(unsafe) var _typeMetadataSectionEnd: _SectionBound
+#endif
 #else
 #warning("Platform-specific implementation missing: Runtime test discovery unavailable (static)")
 private nonisolated(unsafe) let _testContentSectionBegin = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 16)
 private nonisolated(unsafe) let _testContentSectionEnd = _testContentSectionBegin
 #if !SWT_NO_LEGACY_TEST_DISCOVERY
 private nonisolated(unsafe) let _typeMetadataSectionBegin = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 16)
 private nonisolated(unsafe) let _typeMetadataSectionEnd = _typeMetadataSectionBegin
 #endif
 #endif
 // ...
```

These symbols must have unique addresses corresponding to the first byte of the
test content section and the first byte _after_ the test content section,
respectively. Their linker-level names will be platform-dependent: refer to the
linker documentation for your platform to determine what names to place in the
`@_silgen_name` attribute applied to each.

If your target platform statically links Swift Testing but the linker does not
define section bounds symbols, please reach out to us in the Swift forums for
advice.

## C++ stub implementations

Some symbols defined in C and C++ headers, especially "complex" macros, cannot
be represented in Swift. The `_TestingInternals` module includes a header file,
`Stubs.h`, where you can define thin wrappers around these symbols that are
visible to Swift. For example, to use timers on Classic, you'll need to call
`NewTimerUPP()` to define the timer's callback, but that symbol is sometimes
declared as a macro and cannot be called from Swift. You can add a stub function
to `Stubs.h`:

```diff
--- a/Sources/_TestingInternals/include/Stubs.h
+++ b/Sources/_TestingInternals/include/Stubs.h

+#if defined(macintosh)
+static TimerUPP swt_NewTimerUPP(TimerProcPtr userRoutine) {
+  return NewTimerUPP(userRoutine);
+}
+#endif
```

Stub functions should generally be `static` to allow for inlining and when
possible should be named to match the symbols they wrap.

## Unavailable features

You may find that some feature of C++, Swift, or Swift Testing cannot be ported
to your target platform. For example, Swift Testing's `FileHandle` type includes
an `isTTY` property to determine if a file handle refers to a pseudoterminal,
but Classic did not implement pseudoterminals at the file system layer, so
`isTTY` cannot be meaningfully implemented.

For most situations like this one, you can guard the affected code with a
platform conditional and provide a stub implementation:

```diff
--- a/Sources/Testing/Support/FileHandle.swift
+++ b/Sources/Testing/Support/FileHandle.swift

 var isTTY: Bool {
 #if SWT_TARGET_OS_APPLE || os(Linux) || os(FreeBSD) || os(OpenBSD) || os(Android) || os(WASI)
   // ...
+#elseif os(Classic)
+  return false
 #else
 #warning("Platform-specific implementation missing: cannot tell if a file is a TTY")
   return false
 #endif
 }
```

If another function in Swift Testing asks if a file is a TTY, it will then
always get a result of `false` (which is always the correct result on Classic.)
No further changes are needed in this case.

If your target platform is missing some feature that is used pervasively
throughout Swift Testing, this approach may be insufficient. Please reach out to
us in the Swift forums for advice.

## Adding new dependencies

Avoid adding new Swift package or toolchain library dependencies. Swift Testing
needs to support running tests for all Swift targets except, for the moment, the
Swift standard library itself. Adding a dependency on another Swift component
means that that component may be unable to link to Swift Testing. If you find
yourself needing to link to a Swift component, please reach out to us in the
Swift forums for advice.

> [!WARNING]
> Swift Testing has some dependencies on Foundation, specifically to support our
> JSON event stream. Do not add new uses of Foundation without talking to us
> first. If you _do_ add any new uses of Foundation (including any related
> modules such as CoreFoundation or FoundationEssentials), they _must_ be
> imported using the `private` keyword.

It is acceptable to add dependencies on C or C++ modules that are included by
default in the new target platform. For example, Classic always includes the
[Memory Manager](https://developer.apple.com/library/archive/documentation/mac/pdf/Memory/Memory_Preface.pdf),
so there is no problem using it. On the other hand, [WorldScript](https://developer.apple.com/library/archive/documentation/mac/pdf/Text.pdf)
is an optional component, so the Classic port of Swift Testing must be able to
function when it is not installed.

If you need Swift Testing to link to additional libraries at build time, be sure
to update both the [package manifest](https://github.com/swiftlang/swift-testing/blob/main/Package.swift)
and the library target's [CMake script](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/CMakeLists.txt)
to include the necessary linker flags.

## Adding CI jobs for the new platform

The Swift project maintains a set of CI jobs that target various platforms. To
add CI jobs for Swift Testing or the Swift toolchain, please contact the CI
maintainers on the Swift forums.

If you wish to host your own CI jobs, let us know: we'd be happy to run them as
part of Swift Testing's regular development cycle.
