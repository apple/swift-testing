//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension CollectionDifference.Change {
  /// The element that was changed.
  var element: ChangeElement {
    switch self {
    case let .insert(offset: _, element: result, associatedWith: _), let .remove(offset: _, element: result, associatedWith: _):
      return result
    }
  }
}
