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

#if SWT_BUILDING_WITH_CMAKE
@_implementationOnly import _TestingInternals
#else
private import _TestingInternals
#endif

@Suite("ABI entry point tests")
struct ABIEntryPointTests {
  @available(*, deprecated)
  @Test func v0_experimental() async throws {
    var arguments = __CommandLineArguments_v0()
    arguments.filter = ["NonExistentTestThatMatchesNothingHopefully"]
    arguments.eventStreamVersion = 0
    arguments.verbosity = .min

    let result = try await _invokeEntryPointV0Experimental(passing: arguments) { recordJSON in
      let record = try! JSON.decode(ABIv0.Record.self, from: recordJSON)
      _ = record.version
    }

    #expect(result == EXIT_SUCCESS)
  }

  @available(*, deprecated)
  @Test("v0 experimental entry point with a large number of filter arguments")
  func v0_experimental_manyFilters() async throws {
    var arguments = __CommandLineArguments_v0()
    arguments.filter = (1...100).map { "NonExistentTestThatMatchesNothingHopefully_\($0)" }
    arguments.eventStreamVersion = 0
    arguments.verbosity = .min

    let result = try await _invokeEntryPointV0Experimental(passing: arguments)

    #expect(result == EXIT_SUCCESS)
  }

  @available(*, deprecated)
  private func _invokeEntryPointV0Experimental(
    passing arguments: __CommandLineArguments_v0,
    recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void = { _ in }
  ) async throws -> CInt {
#if !os(Linux) && !SWT_NO_DYNAMIC_LINKING
    // Get the ABI entry point by dynamically looking it up at runtime.
    //
    // NOTE: The standard Linux linker does not allow exporting symbols from
    // executables, so dlsym() does not let us find this function on that
    // platform when built as an executable rather than a dynamic library.
    let copyABIEntryPoint_v0 = try #require(
      symbol(named: "swt_copyABIEntryPoint_v0").map {
        unsafeBitCast($0, to: (@convention(c) () -> UnsafeMutableRawPointer).self)
      }
    )
#endif
    let abiEntryPoint = copyABIEntryPoint_v0().assumingMemoryBound(to: ABIEntryPoint_v0.self)
    defer {
      abiEntryPoint.deinitialize(count: 1)
      abiEntryPoint.deallocate()
    }

    let argumentsJSON = try JSON.withEncoding(of: arguments) { argumentsJSON in
      let result = UnsafeMutableRawBufferPointer.allocate(byteCount: argumentsJSON.count, alignment: 1)
      result.copyMemory(from: argumentsJSON)
      return result
    }
    defer {
      argumentsJSON.deallocate()
    }

    // Call the entry point function.
    return try await abiEntryPoint.pointee(.init(argumentsJSON), recordHandler)
  }

  @Test func v0() async throws {
    var arguments = __CommandLineArguments_v0()
    arguments.filter = ["NonExistentTestThatMatchesNothingHopefully"]
    arguments.eventStreamVersion = 0
    arguments.verbosity = .min

    let result = try await _invokeEntryPointV0(passing: arguments) { recordJSON in
      let record = try! JSON.decode(ABIv0.Record.self, from: recordJSON)
      _ = record.version
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
        let record = try! JSON.decode(ABIv0.Record.self, from: recordJSON)
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
#if !os(Linux) && !SWT_NO_DYNAMIC_LINKING
    // Get the ABI entry point by dynamically looking it up at runtime.
    //
    // NOTE: The standard Linux linker does not allow exporting symbols from
    // executables, so dlsym() does not let us find this function on that
    // platform when built as an executable rather than a dynamic library.
    let abiv0_getEntryPoint = try #require(
      symbol(named: "swt_abiv0_getEntryPoint").map {
        unsafeBitCast($0, to: (@convention(c) () -> UnsafeRawPointer).self)
      }
    )
#endif
    let abiEntryPoint = unsafeBitCast(abiv0_getEntryPoint(), to: ABIv0.EntryPoint.self)

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
}
#endif
