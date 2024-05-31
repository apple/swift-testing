//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#include "Discovery.h"

#include <cstdint>
#include <cstring>
#include <type_traits>
#include <cstdio>

#pragma mark Swift ABI

#if defined(__PTRAUTH_INTRINSICS__)
#include <ptrauth.h>
#define SWT_PTRAUTH __ptrauth
#else
#define SWT_PTRAUTH(...)
#endif
#define SWT_PTRAUTH_SWIFT_TYPE_DESCRIPTOR SWT_PTRAUTH(ptrauth_key_process_independent_data, 1, 0xae86)

/// A type representing a pointer relative to itself.
///
/// This type is derived from `RelativeDirectPointerIntPair` in the Swift
/// repository.
template <typename T, int32_t maskValue = 0>
struct SWTRelativePointer {
private:
  int32_t _offset;

public:
  SWTRelativePointer(const SWTRelativePointer&) = delete;
  SWTRelativePointer(const SWTRelativePointer&&) = delete;
  SWTRelativePointer& operator =(const SWTRelativePointer&) = delete;
  SWTRelativePointer& operator =(const SWTRelativePointer&&) = delete;

  int32_t getRawValue(void) const {
    return _offset;
  }

  const T *_Nullable get(void) const& {
    int32_t maskedOffset = getRawValue() & ~maskValue;
    if (maskedOffset == 0) {
      return nullptr;
    }

    auto offset = static_cast<uintptr_t>(static_cast<intptr_t>(maskedOffset));
    auto result = reinterpret_cast<void *>(reinterpret_cast<uintptr_t>(this) + offset);
#if defined(__PTRAUTH_INTRINSICS__)
    if (std::is_function_v<T> && result) {
      result = ptrauth_strip(result, ptrauth_key_function_pointer);
      result = ptrauth_sign_unauthenticated(result, ptrauth_key_function_pointer, 0);
    }
#endif
    return reinterpret_cast<const T *>(result);
  }

  const T *_Nullable operator ->(void) const& {
    return get();
  }
};

/// A type representing a pointer relative to itself with low bits reserved for
/// use as flags.
///
/// This type is derived from `RelativeDirectPointerIntPair` in the Swift
/// repository.
template <typename T, typename I, int32_t maskValue = (alignof(int32_t) - 1)>
struct SWTRelativePointerIntPair: public SWTRelativePointer<T, maskValue> {
  I getInt() const & {
    return I(this->getRawValue() & maskValue);
  }
};

/// A type representing a metatype as constructed during compilation of a Swift
/// module.
///
/// This type is derived from `TargetTypeContextDescriptor` in the Swift
/// repository.
struct SWTTypeContextDescriptor {
private:
  uint32_t _flags;
  SWTRelativePointer<void> _parent;
  SWTRelativePointer<char> _name;

  struct MetadataAccessResponse {
    void *value;
    size_t state;
  };
  using MetadataAccessFunction = __attribute__((swiftcall)) MetadataAccessResponse(size_t);
  SWTRelativePointer<MetadataAccessFunction> _metadataAccessFunction;

public:
  const char *_Nullable getName(void) const& {
    return _name.get();
  }

  void *_Nullable getMetadata(void) const& {
    if (auto fp = _metadataAccessFunction.get()) {
      return (* fp)(0xFF).value;
    }
    return nullptr;
  }

  bool isGeneric(void) const& {
    return (_flags & 0x80u) != 0;
  }
};

/// A type representing a relative pointer to a type descriptor.
///
/// This type is derived from `TargetTypeMetadataRecord` in the Swift
/// repository.
struct SWTTypeMetadataRecord {
private:
  SWTRelativePointerIntPair<void, unsigned int> _pointer;

public:
  const SWTTypeContextDescriptor *_Nullable getContextDescriptor(void) const {
    switch (_pointer.getInt()) {
    case 0: // Direct pointer.
      return reinterpret_cast<const SWTTypeContextDescriptor *>(_pointer.get());
    case 1: // Indirect pointer (pointer to a pointer.)
            // The inner pointer is signed when pointer authentication
            // instructions are available.
      if (auto contextDescriptor = reinterpret_cast<SWTTypeContextDescriptor *const SWT_PTRAUTH_SWIFT_TYPE_DESCRIPTOR *>(_pointer.get())) {
        return *contextDescriptor;
      }
      [[fallthrough]];
    default: // Unsupported or invalid.
      return nullptr;
    }
  }
};

#pragma mark -

void swt_enumerateTypesWithNamesContaining(const char *nameSubstring, const void *sectionStart, size_t sectionLength, void *context, SWTTypeEnumerator body) {
  auto records = reinterpret_cast<const SWTTypeMetadataRecord *>(sectionStart);
  size_t recordCount = sectionLength / sizeof(SWTTypeMetadataRecord);

  bool stop = false;
  for (size_t i = 0; i < recordCount && !stop; i++) {
    const auto& record = records[i];

    auto contextDescriptor = record.getContextDescriptor();
    std::fprintf(stderr, "~~~ TR %p -> CD %p\n", &record, contextDescriptor);
    std::fflush(stderr);
    if (!contextDescriptor) {
      // This type metadata record is invalid (or we don't understand how to
      // get its context descriptor), so skip it.
      continue;
    } else if (contextDescriptor->isGeneric()) {
      // Generic types cannot be fully instantiated without generic
      // parameters, which is not something we can know abstractly.
      continue;
    }

    // Check that the type's name passes. This will be more expensive than the
    // checks above, but should be cheaper than realizing the metadata.
    const char *typeName = contextDescriptor->getName();
    bool nameOK = typeName && nullptr != std::strstr(typeName, nameSubstring);
    if (!nameOK) {
      continue;
    }

    if (void *typeMetadata = contextDescriptor->getMetadata()) {
      body(typeMetadata, &stop, context);
    }
  }
}
