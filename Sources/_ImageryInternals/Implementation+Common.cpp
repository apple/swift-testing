//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if defined(__ELF__) || defined(__APPLE__)
#include "Image.h"
#include "Section.h"
#include "Support/Deferred.h"

#include <cstring>

#include <dlfcn.h>

bool sml_getImageContainingAddress(const void *address, SMLImage *outImage) {
  Dl_info info;
  if (dladdr(address, &info)) {
    *outImage = { info.dli_fbase, info.dli_fname };
    return true;
  }

  return false;
}

// MARK: -

void sml_withImageName(const SMLImage *image, void *context, SMLImageNameCallback body) {
  if (image->name) {
    return body(image, image->name, context);
  }

  SMLImage imageCopy;
  if (sml_getImageContainingAddress(image->base, &imageCopy)) {
    return body(image, imageCopy.name, context);
  }

  return body(image, nullptr, context);
}
#endif
