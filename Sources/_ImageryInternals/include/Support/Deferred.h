//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SML_DEFERRED_H)
#define SML_DEFERRED_H
#if defined(__cplusplus)

/// A type that acts similar to a Swift `defer` statement, allowing automatic
/// cleanup without a dedicated helper type or the awkward-to-customize
/// `std::unique_ptr`.
///
/// To use this type, create an instance and set its value to that of some
/// callable value such as a lambda:
///
/// ```c++
/// auto someResource = create(...);
/// SMLDeferred destroyResourceWhenDone = [=] {
///   destroy(someResource);
/// };
/// ```
template <typename A>
struct SMLDeferred {
private:
  A action;

public:
  SMLDeferred(A action): action(action) {}

  ~SMLDeferred() {
    action();
  }
};

#endif
#endif
