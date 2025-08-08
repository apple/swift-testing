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

extension UInt128 {
  init(_ guid: GUID) {
    self = withUnsafeBytes(of: guid) { buffer in
      buffer.baseAddress!.loadUnaligned(as: Self.self)
    }
  }
}

extension GUID {
  init(_ uint128Value: UInt128) {
    self = withUnsafeBytes(of: uint128Value) { buffer in
      buffer.baseAddress!.loadUnaligned(as: Self.self)
    }
  }

  static func ==(lhs: Self, rhs: Self) -> Bool {
    withUnsafeBytes(of: lhs) { lhs in
      withUnsafeBytes(of: rhs) { rhs in
        lhs.elementsEqual(rhs)
      }
    }
  }
}
#endif
