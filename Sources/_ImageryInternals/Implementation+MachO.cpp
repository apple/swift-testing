//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if defined(__APPLE__)
#include "Image.h"
#include "Section.h"
#include "Support/HeapAllocator.h"

#include <cstdlib>
#include <string>
#include <vector>

#include <crt_externs.h>
#include <dispatch/dispatch.h>
#include <mach-o/dyld.h>
#include <mach-o/getsect.h>
#include <objc/runtime.h>
#include <pthread.h>

/// A type that acts as a C++ [Container](https://en.cppreference.com/w/cpp/named_req/Container)
/// and which contains a sequence of Mach headers.
#if __LP64__
using SMLMachHeaderList = std::vector<const mach_header_64 *, SMLHeapAllocator<const mach_header_64 *>>;
#else
using SMLMachHeaderList = std::vector<const mach_header *, SMLHeapAllocator<const mach_header *>>;
#endif

// MARK: - Image

void sml_getMainImage(SMLImage *outImage) {
  outImage->base = _NSGetMachExecuteHeader();
  outImage->name = nullptr;
}

void sml_enumerateImages(void *_Null_unspecified context, SMLImageEnumerator body) {
  /// This list is necessarily mutated while a global libobjc- or dyld-owned
  /// lock is held. Hence, code using this list must avoid potentially
  /// re-entering either library (otherwise it could potentially deadlock.)
  ///
  /// To see how the Swift runtime accomplishes the above goal, see
  /// `ConcurrentReadableArray` in that project's Concurrent.h header. Since the
  /// imagery library is not tasked with the same performance constraints as
  /// Swift's runtime library, we just use a `std::vector` guarded by a readers-
  /// writer lock.
  static constinit SMLMachHeaderList *machHeaders = nullptr;
  static constinit pthread_rwlock_t lock = PTHREAD_RWLOCK_INITIALIZER;

  static constinit dispatch_once_t once = 0;
  dispatch_once_f(&once, nullptr, [] (void *) {
    machHeaders = reinterpret_cast<SMLMachHeaderList *>(std::malloc(sizeof(SMLMachHeaderList)));
    ::new (machHeaders) SMLMachHeaderList();
    machHeaders->reserve(_dyld_image_count());

    _dyld_register_func_for_remove_image([] (const mach_header *mh, intptr_t) {
      if (auto mhn = reinterpret_cast<SMLMachHeaderList::value_type>(mh)) {
        pthread_rwlock_wrlock(&lock); {
          machHeaders->erase(std::remove(machHeaders->begin(), machHeaders->end(), mhn));
        } pthread_rwlock_unlock(&lock);
      }
    });

    objc_addLoadImageFunc([] (const mach_header *mh) {
      if (auto mhn = reinterpret_cast<SMLMachHeaderList::value_type>(mh)) {
        pthread_rwlock_wrlock(&lock); {
          machHeaders->push_back(mhn);
        } pthread_rwlock_unlock(&lock);
      }
    });
  });

  // After the first call sets up the loader hook, all calls take the read lock
  // and iterate over the image list.
  pthread_rwlock_rdlock(&lock); {
    for (auto mh : *machHeaders) {
      SMLImage image = { mh, nullptr };
      bool stop = false;
      body(&image, &stop, context);
      if (stop) {
        break;
      }
    }
  } pthread_rwlock_unlock(&lock);
}

// MARK: - Section

bool sml_findSection(const SMLImage *image, const char *sectionName, SMLSection *outSection) {
  // Split up the complete section name into Mach-O segment and section names
  // separated by an ASCII comma.
  const char *segmentAndSectionName = sectionName;
  const char *comma = std::strchr(sectionName, ',');
  if (!comma) {
    return false;
  }
  std::basic_string<char, std::char_traits<char>, SMLHeapAllocator<char>> segmentName { sectionName };
  segmentName = segmentName.substr(0, comma - sectionName);
  sectionName = comma + 1;

  unsigned long size = 0;
  const void *start = getsectiondata(reinterpret_cast<SMLMachHeaderList::value_type>(image->base), segmentName.c_str(), sectionName, &size);
  if (start && size > 0) {
    outSection->start = start;
    outSection->size = size;
    return true;
  }

  return false;
}
#endif
