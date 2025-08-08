//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if os(Windows)
internal import WinSDK

extension UnsafeMutablePointer<IPropertyBag2> {
  /// Write a floating-point value to this property bag with the given name,
  ///
  /// - Parameters:
  ///   - value: The value to write.
  ///   - propertyName: The name of the property.
  ///
  /// - Throws: If any error occurred writing the property.
  func write(_ value: Float, named propertyName: String) throws {
    let rWrite = propertyName.withCString(encodedAs: UTF16.self) { propertyName in
      var option = PROPBAG2()
      option.pstrName = .init(mutating: propertyName)

      return withUnsafeTemporaryAllocation(of: VARIANT.self, capacity: 1) { variant in
        let variant = variant.baseAddress!
        VariantInit(variant)
        variant.pointee.vt = .init(VT_R4.rawValue)
        variant.pointee.fltVal = value
        return self.pointee.lpVtbl.pointee.Write(self, 1, &option, variant)
      }
    }
    guard rWrite == S_OK else {
      throw ImageAttachmentError.propertyBagWritingFailed(propertyName, rWrite)
    }
  }
}
#endif
