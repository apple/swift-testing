//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if !defined(SML_HEAPALLOCATOR_H)
#define SML_HEAPALLOCATOR_H
#if defined(__cplusplus)

#include <cstdlib>

/// A type that acts as a C++ [Allocator](https://en.cppreference.com/w/cpp/named_req/Allocator)
/// without using global `operator new` or `operator delete`.
///
/// This type is necessary because global `operator new` and `operator delete`
/// can be overridden in developer-supplied code and cause deadlocks or crashes
/// when subsequently used while holding a dyld- or libobjc-owned lock. Using
/// `std::malloc()` and `std::free()` allows the use of C++ container types
/// without this risk.
template<typename T>
struct SMLHeapAllocator {
  using value_type = T;

  T *allocate(size_t count) {
    return reinterpret_cast<T *>(std::calloc(count, sizeof(T)));
  }

  void deallocate(T *ptr, size_t count) {
    std::free(ptr);
  }

  bool operator ==(const SMLHeapAllocator& other) const {
    return true;
  }
};

#endif
#endif
