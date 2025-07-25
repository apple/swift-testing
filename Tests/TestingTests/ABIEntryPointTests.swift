//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Foundation) && !SWT_NO_ABI_ENTRY_POINT
@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing

#if canImport(Foundation)
private import Foundation
#endif
private import _TestingInternals

@Suite("ABI entry point tests")
struct ABIEntryPointTests {
  @Test func v0() async throws {
    var arguments = __CommandLineArguments_v0()
    arguments.filter = ["NonExistentTestThatMatchesNothingHopefully"]
    arguments.eventStreamVersion = 0
    arguments.verbosity = .min

    let result = try await _invokeEntryPointV0(passing: arguments) { recordJSON in
      let record = try! JSON.decode(ABI.Record<ABI.v0>.self, from: recordJSON)
      _ = record.kind
    }

    #expect(result)
  }

  @Test("v0 entry point with a large number of filter arguments")
  func v0_manyFilters() async throws {
    var arguments = __CommandLineArguments_v0()
    arguments.filter = (1...100).map { "NonExistentTestThatMatchesNothingHopefully_\($0)" }
    arguments.eventStreamVersion = 0
    arguments.verbosity = .min

    let result = try await _invokeEntryPointV0(passing: arguments)

    #expect(result)
  }

  @Test("v0 entry point listing tests only")
  func v0_listingTestsOnly() async throws {
    var arguments = __CommandLineArguments_v0()
    arguments.listTests = true
    arguments.eventStreamVersion = 0
    arguments.verbosity = .min

    try await confirmation("Test matched", expectedCount: 1...) { testMatched in
      _ = try await _invokeEntryPointV0(passing: arguments) { recordJSON in
        let record = try! JSON.decode(ABI.Record<ABI.v0>.self, from: recordJSON)
        if case .test = record.kind {
          testMatched()
        } else {
          Issue.record("Unexpected record \(record)")
        }
      }
    }
  }

  private func _invokeEntryPointV0(
    passing arguments: __CommandLineArguments_v0,
    recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void = { _ in }
  ) async throws -> Bool {
#if !os(Linux) && !os(FreeBSD) && !os(Android) && !SWT_NO_DYNAMIC_LINKING
    // Get the ABI entry point by dynamically looking it up at runtime.
    //
    // NOTE: The standard Linux linker does not allow exporting symbols from
    // executables, so dlsym() does not let us find this function on that
    // platform when built as an executable rather than a dynamic library.
    let abiv0_getEntryPoint = try withTestingLibraryImageAddress { testingLibrary in
      try #require(
        symbol(in: testingLibrary, named: "swt_abiv0_getEntryPoint").map {
          castCFunction(at: $0, to: (@convention(c) () -> UnsafeRawPointer).self)
        }
      )
    }
#endif
    let abiEntryPoint = unsafeBitCast(abiv0_getEntryPoint(), to: ABI.v0.EntryPoint.self)

    let argumentsJSON = try JSON.withEncoding(of: arguments) { argumentsJSON in
      let result = UnsafeMutableRawBufferPointer.allocate(byteCount: argumentsJSON.count, alignment: 1)
      result.copyMemory(from: argumentsJSON)
      return result
    }
    defer {
      argumentsJSON.deallocate()
    }

    // Call the entry point function.
    return try await abiEntryPoint(.init(argumentsJSON), recordHandler)
  }

#if canImport(Foundation)
  @Test func decodeEmptyConfiguration() throws {
    let emptyBuffer = UnsafeRawBufferPointer(start: nil, count: 0)
    #expect(throws: DecodingError.self) {
      _ = try JSON.decode(__CommandLineArguments_v0.self, from: emptyBuffer)
    }
  }

  @Test func decodeWrongRecordVersion() throws {
    let record = ABI.Record<ABI.v1>(encoding: Test {})
    let error = try JSON.withEncoding(of: record) { recordJSON in
      try #require(throws: DecodingError.self) {
        _ = try JSON.decode(ABI.Record<ABI.v0>.self, from: recordJSON)
      }
    }
    guard case let .dataCorrupted(context) = error else {
      throw error
    }
    #expect(context.debugDescription == "Unexpected record version 1 (expected 0).")
  }
#endif
}

#if !SWT_NO_DYNAMIC_LINKING
private func withTestingLibraryImageAddress<R>(_ body: (ImageAddress?) throws -> R) throws -> R {
  let addressInTestingLibrary = unsafeBitCast(ABI.v0.entryPoint, to: UnsafeRawPointer.self)

  var testingLibraryAddress: ImageAddress?
#if SWT_TARGET_OS_APPLE
  var info = Dl_info()
  try #require(0 != dladdr(addressInTestingLibrary, &info))

  testingLibraryAddress = dlopen(info.dli_fname, RTLD_NOLOAD)
  try #require(testingLibraryAddress != nil)
  defer {
    dlclose(testingLibraryAddress)
  }
#elseif os(Linux) || os(FreeBSD) || os(Android)
  // When using glibc, dladdr() is only available if __USE_GNU is specified.
#elseif os(Windows)
  let flags = DWORD(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS)
  try addressInTestingLibrary.withMemoryRebound(to: wchar_t.self, capacity: MemoryLayout<UnsafeRawPointer>.stride / MemoryLayout<wchar_t>.stride) { addressInTestingLibrary in
    try #require(GetModuleHandleExW(flags, addressInTestingLibrary, &testingLibraryAddress))
  }
  defer {
    FreeLibrary(testingLibraryAddress)
  }
#else
#warning("Platform-specific implementation missing: cannot find the testing library image the test suite is linked against")
#endif

  return try body(testingLibraryAddress)
}
#endif
#endif
