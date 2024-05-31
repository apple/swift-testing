//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if defined(__ELF__)
#include "Image.h"
#include "Section.h"
#include "Support/Deferred.h"

#include <array>
#include <cstddef>
#include <cstdio>
#include <cstring>

#include <dlfcn.h>
#include <elf.h>
#include <fcntl.h>
#include <link.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <unistd.h>

#if SML_ELF_SECURITY_ENABLED
/// Check whether all mapped memory to a given path in the process' address
/// space refers to the same file on disk.
///
/// - Parameters:
///   - path: The path to inspect.
///   - st: A previously-initialized `stat` structure describing `path`.
///
/// - Returns: Whether all mappings of `path` in the process' address space
///   refer to the same file on disk.
///
/// This function helps mitigate TOCTOU attacks by checking if the file at a
/// given path has been replaced. If any two inode or device numbers do not
/// match those in `st`, the function returns `false` and `path` should be
/// considered compromised.
///
/// The order of operations is important: the calling code must have opened
/// the file _before_ calling this function, otherwise an attacker could
/// substitute the file while this function is running or immediately
/// afterward before the file is opened in this process.
static bool isFileIDConsistent(const char *path, const struct stat& st) {
  FILE *maps = std::fopen("/proc/self/maps", "rb");
  if (!maps) {
    // Couldn't open the file. Bail.
    return false;
  }
  SMLDeferred closeWhenDone = [=] {
    std::fclose(maps);
  };

  // Loop through the lines in the file looking for ones that refer to the
  // same path and check if their inode or device numbers are the same.
  while (!std::feof(maps) && !std::ferror(maps)) {
    unsigned long long devMajor = 0;
    unsigned long long devMinor = 0;
    unsigned long long ino = 0;
    std::array<char, 2048 + 1> mapPath;
    int count = std::fscanf(maps, "%*llx-%*llx %*4c %*llx %llu:%llu %llu %2048[^\n]\n", &devMajor, &devMinor, &ino, &mapPath[0]);
    if (count < 4 || count == EOF) {
      // Failed to read in the expected format. Stop reading.
      return false;
    }
    mapPath.back() = '\0';
    if (0 == std::strcmp(&mapPath[0], path)) {
      if (makedev(devMajor, devMinor) != st.st_dev || ino != st.st_ino) {
        return false;
      }
    }
  }

  if (ferror(maps)) {
    // An error occurred doing I/O. Bail.
    return false;
  }

  return true;
}
#endif

/// Map an ELF image from a file on disk.
///
/// - Parameters:
///   - path: The path to the ELF image on disk.
///   - outSize: On return, the size of the mapped file.
///
/// - Returns: The ELF header of the specified image, or `nullptr` if an
///   error occurred. The caller is responsible for passing this pointer to
///   `munmap()` when done.
///
/// The resulting ELF header is mapped only, not loaded.
static const ElfW(Ehdr) *map(const char *path, size_t *outSize) {
  // Get a file descriptor to the binary.
  int fd = open(path, O_RDONLY);
  if (fd < 0) {
    return nullptr;
  }
  SMLDeferred closeWhenDone = [=] {
    close(fd);
  };

  // Get the size of the binary.
  struct stat st;
  if (0 != fstat(fd, &st)) {
    return nullptr;
  }

#if SML_ELF_SECURITY_ENABLED
  // Check that the file we just opened is the same as the one already
  // loaded into the process.
  bool fileOK = isFileIDConsistent(path, st);
  if (!fileOK) {
    return nullptr;
  }
#endif

  // Map the binary.
  void *result = mmap(nullptr, st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  if (result == MAP_FAILED) {
    return nullptr;
  }

  *outSize = st.st_size;
  return reinterpret_cast<const ElfW(Ehdr) *>(result);
}

// MARK: - Image

void sml_getMainImage(SMLImage *outImage) {
  sml_enumerateImages(outImage, [] (const SMLImage *image, bool *stop, void *context) {
    auto outImage = reinterpret_cast<SMLImage *>(context);
    *outImage = *image;
    *stop = true;
  });
}

void sml_enumerateImages(void *_Null_unspecified context, SMLImageEnumerator body) {
  struct Context {
    void *context;
    SMLImageEnumerator body;
  };
  Context ctx { context, body };
  (void)dl_iterate_phdr([] (struct dl_phdr_info *info, size_t size, void *context) -> int {
    const auto& ctx = *reinterpret_cast<Context *>(context);
    // Find the ehdr loaded into the current process corresponding to the phdr
    // being enumerated. We can do so by looking up the image base for the
    // phdr's address.
    SMLImage image = {};
    if (sml_getImageContainingAddress(info->dlpi_phdr, &image)) {
      bool stop = false;
      ctx.body(&image, &stop, ctx.context);
      if (stop) {
        return -1;
      }
    }

    return 0;
  }, &ctx);
}

// MARK: - Section

bool sml_findSection(const SMLImage *image, const char *sectionName, SMLSection *outSection) {
  auto ehdrLoaded = reinterpret_cast<const ElfW(Ehdr) *>(image->base);
  auto baseLoaded = reinterpret_cast<uintptr_t>(ehdrLoaded);

  if (ehdrLoaded->e_shoff == 0 || ehdrLoaded->e_shstrndx == SHN_UNDEF) {
    // There are no section headers in this ELF image, or there is no string
    // table containing section names.
    return false;
  }

  if (ehdrLoaded->e_shnum == 0 || ehdrLoaded->e_shstrndx == SHN_XINDEX) {
    // The number of sections or the string table section index exceeds
    // SHN_LORESERVE. We don't currently support these edge cases.
    // FIXME: support said edge cases
    return false;
  }

  // Map a complete copy of the image into memory. This copy will include the
  // shdrs (which are not normally mapped for loaded images.) Mapping a file is
  // a bit complicated (but well-understood), so it's factored out into a
  // separate function.
  size_t ehdrMappedSize = 0;
  auto ehdrMapped = map(image->name, &ehdrMappedSize);
  if (!ehdrMapped) {
    // Couldn't map the image. It might have moved.
    return false;
  }
  auto baseMapped = reinterpret_cast<uintptr_t>(ehdrMapped);
  SMLDeferred unmapEhdrWhenDone = [=] {
    munmap(const_cast<ElfW(Ehdr) *>(ehdrMapped), ehdrMappedSize);
  };

  // Find the mapped ehdr's string table.
  auto strtab = reinterpret_cast<const ElfW(Shdr) *>(baseMapped + ehdrMapped->e_shoff + (ehdrMapped->e_shentsize * ehdrMapped->e_shstrndx));
  if (strtab->sh_type == SHT_STRTAB) {
    // Loop through the sections in the image and pass the matching one back.
    auto shdr = reinterpret_cast<const ElfW(Shdr) *>(baseMapped + ehdrMapped->e_shoff);
    for (ElfW(Half) i = 0; i < ehdrMapped->e_shnum; i++) {
      // Figure out the name of this section, then call the callback.
      auto thisSectionName = reinterpret_cast<const char *>(baseMapped + strtab->sh_offset + shdr->sh_name);
      if (thisSectionName && 0 == std::strcmp(sectionName, thisSectionName)) {
        outSection->start = reinterpret_cast<const void *>(baseLoaded + shdr->sh_offset);
        outSection->size = shdr->sh_size;
        auto offset = (unsigned long long)((uintptr_t)outSection->start - (uintptr_t)baseLoaded);
        return true;
      }
      
      shdr = reinterpret_cast<const ElfW(Shdr) *>(reinterpret_cast<uintptr_t>(shdr) + ehdrMapped->e_shentsize);
    }
  }

  return true;
}
#endif
