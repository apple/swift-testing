# Attachments

<!--
This source file is part of the Swift.org open source project

Copyright (c) 2024–2025 Apple Inc. and the Swift project authors
Licensed under Apache License v2.0 with Runtime Library Exception

See https://swift.org/LICENSE.txt for license information
See https://swift.org/CONTRIBUTORS.txt for Swift project authors
-->

Attach values to tests to help diagnose issues and gather feedback.

## Overview

Attach values such as strings and files to tests. Implement the ``Attachable``
protocol to create your own attachable types.

### Attach data or strings

If your test produces encoded data that you want to save as an attachment, you
can call ``Attachment/record(_:named:sourceLocation:)``.

```swift
struct SalesReport { ... }

@Test func `sales report adds up`() async throws {
  let salesReport = await generateSalesReport()
  try salesReport.validate()
  let bytes: [UInt8] = try salesReport.convertToCSV()
  Attachment.record(bytes, named: "sales report.csv")
}
```

You can attach an instance of [`Array<UInt8>`](https://developer.apple.com/documentation/swift/array),
[`ContiguousArray<UInt8>`](https://developer.apple.com/documentation/swift/contiguousarray),
[`ArraySlice<UInt8>`](https://developer.apple.com/documentation/swift/arrayslice),
or [`Data`](https://developer.apple.com/documentation/foundation/data) because
these types automatically conform to ``Attachable``.

You can also attach an instance of [`String`](https://developer.apple.com/documentation/swift/string)
or [`Substring`](https://developer.apple.com/documentation/swift/substring). The
testing library treats attached strings as UTF-8 text files. If you want to save
a string as an attachment using a different encoding, convert it to [`Data`](https://developer.apple.com/documentation/foundation/data)
using [`data(using:allowLossyConversion:)`](https://developer.apple.com/documentation/swift/stringprotocol/data(using:allowlossyconversion:))
and attach the resulting data instead of the original string.

### Attach encodable values

If you have a value you want to save as an attachment that conforms to either
[`Encodable`](https://developer.apple.com/documentation/swift/encodable) or
[`NSSecureCoding`](https://developer.apple.com/documentation/foundation/nssecurecoding),
you can create an instance of ``Attachment`` from it when you import the
[Foundation](https://developer.apple.com/documentation/foundation) module.

```swift
import Testing
import Foundation

struct SalesReport: Encodable { ... }

@Test func `sales report adds up`() async throws {
  let salesReport = await generateSalesReport()
  try salesReport.validate()
  let attachment = try Attachment(encoding: salesReport)
  Attachment.record(attachment)
}
```

By default, the testing library encodes values as JSON if they conform to [`Encodable`](https://developer.apple.com/documentation/swift/encodable)
or as binary property lists if they conform to [`NSSecureCoding`](https://developer.apple.com/documentation/foundation/nssecurecoding).
You can customize the resulting encoded data further by passing an encoding
format or a top-level encoder.

| Type Conforms To | Customize With |
|-|-|
| [`Encodable`](https://developer.apple.com/documentation/swift/encodable) | ``AttachableEncodingFormat``, [`JSONEncoder`](https://developer.apple.com/documentation/foundation/jsonencoder), [`PropertyListEncoder`](https://developer.apple.com/documentation/foundation/propertylistencoder), or [`TopLevelEncoder`](https://developer.apple.com/documentation/combine/toplevelencoder) |
| [`NSSecureCoding`](https://developer.apple.com/documentation/foundation/nssecurecoding) | [`PropertyListSerialization.PropertyListFormat`](https://developer.apple.com/documentation/foundation/propertylistserialization/propertylistformat) | 

For example, to attach a value to your test as an XML property list:

```swift
import Testing
import Foundation

struct SalesReport: Encodable { ... }

@Test func `sales report adds up`() async throws {
  let salesReport = await generateSalesReport()
  try salesReport.validate()
  let attachment = try Attachment(
    encoding: salesReport,
    as: .propertyListFormat(.xml)
  )
  Attachment.record(attachment)
}
```

- Important: The testing library provides these ``Attachment`` initializers only
if your test target imports the [Foundation](https://developer.apple.com/documentation/foundation)
module.

### Attach transferable values

If you have a value you want to save as an attachment that conforms to
[`Transferable`](https://developer.apple.com/documentation/CoreTransferable/Transferable),
you can create an instance of ``Attachment`` from it when you import the
[Core Transferable](https://developer.apple.com/documentation/coretransferable)
module.

```swift
import Testing
import CoreTransferable

struct SalesReport: Transferable { ... }

@Test func `sales report adds up`() async throws {
  let salesReport = await generateSalesReport()
  try salesReport.validate()
  let attachment = try await Attachment(exporting: salesReport)
  Attachment.record(attachment)
}
```

- Important: The testing library provides this ``Attachment`` initializer only
  if your test target imports the [Core Transferable](https://developer.apple.com/documentation/coretransferable)
  module.

When you create an attachment from a transferable value, the testing library
calls the value's [`exported(as:)`](https://developer.apple.com/documentation/coretransferable/transferable/exported(as:))
function. By default, the testing library calls the value's [`exportedContentTypes(_:)`](https://developer.apple.com/documentation/coretransferable/transferable/exportedcontenttypes(_:))
function and uses the first returned content type that conforms to [`UTType.data`](https://developer.apple.com/documentation/uniformtypeidentifiers/uttype-swift.struct/data).
If you want to use a different format for the attachment, you can pass another
content type supported by the attachable value when you create the attachment.

```swift
let attachment = try await Attachment(exporting: salesReport, as: .pdf)
```

### Attach files and directories

If you have a file you want to save as an attachment, you can attach it using
its file URL. The testing library needs to read or map the file before attaching it
to your test, and those operations can fail, so you need to explicitly create an
instance of ``Attachment`` before you record it.

```swift
import Foundation

@Test func `sales report adds up`() async throws {
  let salesReport = await generateSalesReport()
  try salesReport.validate()
  let salesReportURL = try salesReport.save()
  let attachment = try await Attachment(contentsOf: salesReportURL)
  Attachment.record(attachment)
}
```

You can also attach a directory to a test using its file URL. When you attach a
directory to a test, the testing library creates a ZIP file containing the
directory's contents, then attaches that ZIP file in place of the directory.

### Attach images

You can attach instances of the following system-provided image types to a test:

| Platform | Supported types |
|-|-|
| macOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`NSImage`](https://developer.apple.com/documentation/appkit/nsimage) |
| iOS, tvOS, and visionOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`CIImage`](https://developer.apple.com/documentation/coreimage/ciimage), [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage) |
| watchOS | [`CGImage`](https://developer.apple.com/documentation/coregraphics/cgimage), [`UIImage`](https://developer.apple.com/documentation/uikit/uiimage) |
| Windows | [`HBITMAP`](https://learn.microsoft.com/en-us/windows/win32/gdi/bitmaps), [`HICON`](https://learn.microsoft.com/en-us/windows/win32/menurc/icons), [`IWICBitmapSource`](https://learn.microsoft.com/en-us/windows/win32/api/wincodec/nn-wincodec-iwicbitmapsource) (including its subclasses declared by Windows Imaging Component) |

When you attach an image to a test, you can specify the image format to use in
addition to a preferred name.

```swift
struct SalesReport { ... }

@Test func `sales report adds up`() async throws {
  let salesReport = await generateSalesReport()
  let image = try salesReport.renderTrendsGraph()
  Attachment.record(image, named: "sales report", as: .png)
}
```

If you don't specify an image format when attaching an image to a test, the
testing library selects the format to use based on the preferred name you pass.

### Attach other values

If you have a value that needs a custom encoded representation when you save it
as an attachment, implement ``Attachable/withUnsafeBytes(for:_:)``. The
implementation of this function calls its `body` argument and passes the encoded
representation of `self` or, if a failure occurs, throws an error representing
that failure.

```swift
struct SalesReport { ... }

extension SalesReport: Attachable {
  borrowing func withUnsafeBytes<R>(
    for attachment: borrowing Attachment<Self>,
    _ body: (UnsafeRawBufferPointer) throws -> R
  ) throws -> R {
    let bytes = try salesReport.convertToCSV() // might fail to convert to CSV
    return try bytes.withUnsafeBytes { buffer in // rethrows errors from `body`
      try body(buffer)
    }
  }
}
```

If your type conforms to [`Sendable`](https://developer.apple.com/documentation/swift/sendable),
the testing library avoids calling this function until it needs to save the
attachment. If your type  _doesn't_ conform to [`Sendable`](https://developer.apple.com/documentation/swift/sendable),
the testing library calls this function as soon as you record the attachment.

#### Customize attachment behavior

If you can reliably estimate in advance how large the encoded representation
will be, implement ``Attachable/estimatedAttachmentByteCount``. The testing
library uses the value of this property as a hint to optimize memory and disk
usage.

```swift
extension SalesReport: Attachable {
  ...

  var estimatedAttachmentByteCount: Int? {
    return self.entries.count * 123
  }
}
```

You can also implement ``Attachable/preferredName(for:basedOn:)`` if you want to
customize the name of the attachment when saving it.

```swift
extension SalesReport: Attachable {
  ...

  borrowing func preferredName(
    for attachment: borrowing Attachment<Self>,
    basedOn suggestedName: String
  ) -> String {
    if suggestedName.contains(".") {
      // The name already contains a path extension, so don't append another.
      return suggestedName
    }

    // Append ".csv" to the name so the resulting file opens as a spreadsheet.
    return "\(suggestedName).csv"
  }
}
```

### Inspect attachments after a test run ends

By default, the testing library saves your attachments as soon as you call
``Attachment/record(_:sourceLocation:)`` or
``Attachment/record(_:named:sourceLocation:)``. You can access saved attachments
after your tests finish running:

- When using Xcode, you can access attachments from the test report.
- When using Visual Studio Code, the testing library saves attachments to
  `.build/attachments` by default. Visual Studio Code reports the paths to
  individual attachments in its Tests Results panel.
- When using Swift Package Manager's `swift test` command, you can pass the
  `--attachments-path` option. The testing library creates a directory at the
  specified path and saves attachments to it.

  If you do not pass the `--attachments-path` option, the testing library does
  not save any attachments you record.

## Topics

### Attaching values to tests

- ``Attachment``
- ``Attachable``
- ``AttachableWrapper``

### Attaching encodable values to tests

- ``AttachableEncodingFormat``

<!-- TODO: set up DocC content for overlays if possible
### Attaching files to tests

- ``Attachment/init(contentsOf:named:sourceLocation:)``
-->

### Attaching images to tests

- ``AttachableAsImage``
- ``AttachableImageFormat``
- ``Attachment/init(_:named:as:sourceLocation:)``
- ``Attachment/record(_:named:as:sourceLocation:)``
