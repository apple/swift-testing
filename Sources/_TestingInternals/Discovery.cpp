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

#include <atomic>
#include <cstring>
#include <iterator>
#include <type_traits>
#include <vector>

#if defined(SWT_NO_DYNAMIC_LINKING)
#include <algorithm>
#elif defined(__APPLE__)
#include <dispatch/dispatch.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <objc/runtime.h>
#include <os/lock.h>
#endif

/// Enumerate over all Swift images in the current process.
///
/// - Parameters:
///   - body: A function to call once for every image in the current process
///     that contains Swift code. A reference to an instance of
///     ``SWTMetadataSections`` is passed to this function for each image.
template <typename ImageEnumerator>
static void enumerateImages(const ImageEnumerator& body);

#pragma mark - Swift ABI

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

/// Specifies the address range corresponding to a section.
struct SWTMetadataSectionRange {
  uintptr_t start;
  size_t length;
};

/// Identifies the address space ranges for the Swift metadata required by the
/// Swift runtime.
///
/// - Note: Most of the fields in this structure are zeroed on Apple platforms
///   since we don't need them. On Linux and Windows, they are generally
///   populated (as provided by the Swift runtime.) The following fields can be
///   relied upon:
///
///   - ``version``
///   - ``baseAddress`` (unless `SWT_NO_DYNAMIC_LINKING` is defined.)
///   - ``swift5_type_metadata``
///   - ``swift5_tests`` (if ``version`` is at least equal to
///     ``SWT_METADATA_SECTION_MINIMUM_VERSION_WITH_TESTS``.)
struct SWTMetadataSections {
  uintptr_t version;
  std::atomic<const void *> baseAddress;

  void *unused0;
  void *unused1;

  SWTMetadataSectionRange swift5_protocols;
  SWTMetadataSectionRange swift5_protocol_conformances;
  SWTMetadataSectionRange swift5_type_metadata;
  SWTMetadataSectionRange swift5_typeref;
  SWTMetadataSectionRange swift5_reflstr;
  SWTMetadataSectionRange swift5_fieldmd;
  SWTMetadataSectionRange swift5_assocty;
  SWTMetadataSectionRange swift5_replace;
  SWTMetadataSectionRange swift5_replac2;
  SWTMetadataSectionRange swift5_builtin;
  SWTMetadataSectionRange swift5_capture;
  SWTMetadataSectionRange swift5_mpenum;
  SWTMetadataSectionRange swift5_accessible_functions;
  SWTMetadataSectionRange swift5_runtime_attributes;
  SWTMetadataSectionRange swift5_tests;
};

/// The minimum value of ``SWTMetadataSections/version`` if that instance of
/// ``SWTMetadataSections`` contains the ``SWTMetadataSections/swift5_tests``
/// field.
static constexpr uintptr_t SWT_METADATA_SECTION_MINIMUM_VERSION_WITH_TESTS = 4;

#if defined(SWT_NO_DYNAMIC_LINKING)
#pragma mark - Statically-linked implementation

// This environment does not have a dynamic linker/loader. Therefore, there is
// only one image (this one) with Swift code in it.
// SEE: https://github.com/apple/swift/tree/main/stdlib/public/runtime/ImageInspectionStatic.cpp

extern "C" const char typesSectionBegin __asm("section$start$__TEXT$__swift5_types");
extern "C" const char typesSectionEnd __asm("section$end$__TEXT$__swift5_types");

extern "C" const char testsSectionBegin __asm("section$start$__DATA_CONST$__swift5_tests");
extern "C" const char testsSectionEnd __asm("section$end$__DATA_CONST$__swift5_tests");

// Ensure the tests section is actually emitted.
__attribute__((used)) __attribute__((section("__DATA_CONST,__swift5_tests")))
constinit const SWTTestGetter ensureTestSectionIsEmitted = std::make_pair(nullptr, nullptr);

template <typename ImageEnumerator>
static void enumerateImages(const ImageEnumerator& body) {
  SWTMetadataSections sections = {};

  auto typesSectionSize = std::distance(&typesSectionBegin, &typesSectionEnd);
  sections.swift5_type_metadata = { reinterpret_cast<uintptr_t>(&typesSectionBegin), typesSectionSize };

  auto testsSectionSize = std::distance(&testsSectionBegin, &testsSectionEnd);
  if (testsSectionSize > sizeof(SWTTestGetter)) {
    // Account for the `ensureTestSectionIsEmitted` value above. If it's the
    // only value in the section, the section is empty.
    sections.version = SWT_METADATA_SECTION_MINIMUM_VERSION_WITH_TESTS;
    sections.swift5_tests = { &testsSectionBegin, testsSectionSize };
  }

  body(sections);
}

#elif defined(__APPLE__)
#pragma mark - Apple implementation

/// A type that acts as a C++ [Allocator](https://en.cppreference.com/w/cpp/named_req/Allocator)
/// without using global `operator new` or `operator delete`.
///
/// This type is necessary because global `operator new` and `operator delete`
/// can be overridden in developer-supplied code and cause deadlocks or crashes
/// when subsequently used while holding a dyld- or libobjc-owned lock. Using
/// `std::malloc()` and `std::free()` allows the use of C++ container types
/// without this risk.
template<typename T>
struct SWTHeapAllocator {
  using value_type = T;

  T *allocate(size_t count) {
    return reinterpret_cast<T *>(std::calloc(count, sizeof(T)));
  }

  void deallocate(T *ptr, size_t count) {
    std::free(ptr);
  }
};

/// A type that acts as a C++ [Container](https://en.cppreference.com/w/cpp/named_req/Container)
/// and which contains a sequence of Mach headers.
#if __LP64__
using SWTMachHeaderList = std::vector<const mach_header_64 *, SWTHeapAllocator<const mach_header_64 *>>;
#else
using SWTMachHeaderList = std::vector<const mach_header *, SWTHeapAllocator<const mach_header *>>;
#endif

/// Get a copy of the currently-loaded Mach headers list.
///
/// - Returns: A list of Mach headers loaded into the current process. The order
///   of the resulting list is unspecified.
///
/// On non-Apple platforms, the `swift_enumerateAllMetadataSections()` function
/// exported by the runtime serves the same purpose as this function.
static SWTMachHeaderList getMachHeaders(void) {
  /// This list is necessarily mutated while a global libobjc- or dyld-owned
  /// lock is held. Hence, code using this list must avoid potentially
  /// re-entering either library (otherwise it could potentially deadlock.)
  ///
  /// To see how the Swift runtime accomplishes the above goal, see
  /// `ConcurrentReadableArray` in that project's Concurrent.h header. Since the
  /// testing library is not tasked with the same performance constraints as
  /// Swift's runtime library, we just use a `std::vector` guarded by an unfair
  /// lock.
  static constinit SWTMachHeaderList *machHeaders = nullptr;
  static constinit os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;

  static constinit dispatch_once_t once = 0;
  dispatch_once_f(&once, nullptr, [] (void *) {
    machHeaders = reinterpret_cast<SWTMachHeaderList *>(std::malloc(sizeof(SWTMachHeaderList)));
    ::new (machHeaders) SWTMachHeaderList();
    machHeaders->reserve(_dyld_image_count());

    objc_addLoadImageFunc([] (const mach_header *mh) {
      auto mhn = reinterpret_cast<SWTMachHeaderList::value_type>(mh);

      // Ignore this Mach header if it is in the shared cache. On platforms that
      // support it (Darwin), most system images are containined in this range.
      // System images can be expected not to contain test declarations, so we
      // don't need to walk them.
      if (mhn->flags & MH_DYLIB_IN_CACHE) {
        return;
      }

      // Only store the mach header address if the image contains Swift data.
      // Swift does not support unloading images, but images that do not contain
      // Swift code may be unloaded at runtime and later crash
      // the testing library when it calls enumerateTypeMetadataSections().
      unsigned long size = 0;
      if (getsectiondata(mhn, SEG_TEXT, "__swift5_types", &size)) {
        os_unfair_lock_lock(&lock); {
          machHeaders->push_back(mhn);
        } os_unfair_lock_unlock(&lock);
      }
    });
  });

  // After the first call sets up the loader hook, all calls take the lock and
  // make a copy of whatever has been loaded so far.
  SWTMachHeaderList result;
  os_unfair_lock_lock(&lock); {
    result = *machHeaders;
  } os_unfair_lock_unlock(&lock);
  return result;
}

template <typename ImageEnumerator>
static void enumerateImages(const ImageEnumerator& body) {
  SWTMachHeaderList machHeaders = getMachHeaders();
  for (auto mh : machHeaders) {
    SWTMetadataSections sections = {};
    sections.baseAddress.store(mh, std::memory_order_relaxed);

    unsigned long typesSectionSize = 0;
    const void *typesSection = getsectiondata(mh, SEG_TEXT, "__swift5_types", &typesSectionSize);
    if (typesSection && typesSectionSize > 0) {
      sections.swift5_type_metadata = { reinterpret_cast<uintptr_t>(typesSection), typesSectionSize };
    }

    unsigned long testsSectionSize = 0;
    const void *testsSection = getsectiondata(mh, "__DATA_CONST", "__swift5_tests", &testsSectionSize);
    if (testsSection && testsSectionSize > 0) {
      sections.version = SWT_METADATA_SECTION_MINIMUM_VERSION_WITH_TESTS;
      sections.swift5_tests = { reinterpret_cast<uintptr_t>(testsSection), testsSectionSize };
    }

    body(sections);
  }
}

#elif defined(__linux__) || defined(_WIN32) || defined(__wasi__)
#pragma mark - Linux/Windows implementation

/// A function exported by the Swift runtime that enumerates all metadata
/// sections loaded into the current process.
SWT_IMPORT_FROM_STDLIB void swift_enumerateAllMetadataSections(
  bool (* body)(const SWTMetadataSections *sections, void *context),
  void *context
);

template <typename ImageEnumerator>
static void enumerateImages(const ImageEnumerator& body) {
  swift_enumerateAllMetadataSections([] (const SWTMetadataSections *sections, void *context) {
    const auto& body = *reinterpret_cast<const ImageEnumerator *>(context);
    body(*sections);
    return true;
  }, const_cast<ImageEnumerator *>(&body));
}
#else
#warning Platform-specific implementation missing: Runtime test discovery unavailable
template <typename SectionEnumerator>
static void enumerateTypeMetadataSections(const SectionEnumerator& body) {}
#endif

#pragma mark -

void swt_enumerateTypesWithNamesContaining(const char *nameSubstring, void *context, SWTTypeEnumerator body) {
  enumerateImages([=] (const SWTMetadataSections& sections) {
    // If this image has a tests section, then it should be used instead of the
    // image's type metadata section.
    if (sections.version >= SWT_METADATA_SECTION_MINIMUM_VERSION_WITH_TESTS) {
      const auto& section = sections.swift5_tests;
      if (section.start != 0 && section.length > 0) {
        #error Disrupts exit tests by preventing their discovery. Need to plumb through whether or not to prefer tests section.
        return; // continue
      }
    }

    if (auto records = reinterpret_cast<const SWTTypeMetadataRecord *>(sections.swift5_type_metadata.start)) {
      size_t recordCount = sections.swift5_type_metadata.length / sizeof(SWTTypeMetadataRecord);
      bool stop = false;
      for (size_t i = 0; i < recordCount && !stop; i++) {
        const auto& record = records[i];

        auto contextDescriptor = record.getContextDescriptor();
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
  });
}

void swt_enumerateTestGetters(void *_Null_unspecified context, SWTTestGetterEnumerator body) {
  enumerateImages([=] (const SWTMetadataSections& sections) {
    if (sections.version >= SWT_METADATA_SECTION_MINIMUM_VERSION_WITH_TESTS) {
      if (auto fps = reinterpret_cast<const SWTTestGetter *>(sections.swift5_tests.start)) {
        size_t fpCount = sections.swift5_tests.length / sizeof(SWTTestGetter);
        for (size_t i = 0; i < fpCount; i++) {
          if (auto fp = fps[i]) {
            body(fp, context);
          }
        }
      }
    }
  });
}
