//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

#if canImport(Foundation)
@testable @_spi(Experimental) @_spi(ForToolsIntegrationOnly) import Testing
import Foundation

@Suite("Advanced Console Output Recorder Tests")
struct AdvancedConsoleOutputRecorderTests {
  final class Stream: TextOutputStream, Sendable {
    let buffer = Locked<String>(rawValue: "")

    @Sendable func write(_ string: String) {
      buffer.withLock {
        $0.append(string)
      }
    }
  }

  @Test("Recorder initialization with default options")
  func recorderInitialization() {
    let stream = Stream()
    let recorder = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>(writingUsing: stream.write)
    
    // Verify the recorder was created successfully and has expected defaults
    #expect(recorder.options.base.useANSIEscapeCodes == false) // Default for non-TTY
  }

  @Test("Recorder initialization with custom options")
  func recorderInitializationWithCustomOptions() {
    let stream = Stream()
    var options = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>.Options()
    options.base.useANSIEscapeCodes = true
    
    let recorder = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>(
      options: options,
      writingUsing: stream.write
    )
    
    // Verify the custom options were applied
    #expect(recorder.options.base.useANSIEscapeCodes == true)
  }

  @Test("Basic event recording produces output")
  func basicEventRecording() async {
    let stream = Stream()
    
    var configuration = Configuration()
    let eventRecorder = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }
    
    // Run a simple test to generate events
    await Test(name: "Sample Test") {
      #expect(Bool(true))
    }.run(configuration: configuration)
    
    let buffer = stream.buffer.rawValue
    // Verify that the hierarchical output was generated
    #expect(buffer.contains("HIERARCHICAL TEST RESULTS"))
    #expect(buffer.contains("Test run started"))
  }

  @Test("Hierarchical output structure is generated")
  func hierarchicalOutputStructure() async {
    let stream = Stream()
    
    var configuration = Configuration()
    let eventRecorder = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }
    
    // Run tests that will create a hierarchy
    await runTest(for: HierarchicalTestSuite.self, configuration: configuration)
    
    let buffer = stream.buffer.rawValue
    
    // Verify hierarchical output headers are generated
    #expect(buffer.contains("HIERARCHICAL TEST RESULTS"))
    #expect(buffer.contains("completed"))
    
    // Should contain tree structure characters (Unicode or ASCII fallback)
    #expect(buffer.contains("├─") || buffer.contains("╰─") || buffer.contains("┌─") ||
            buffer.contains("|-") || buffer.contains("`-") || buffer.contains(".-"))
  }

  @Test("Failed test details are properly formatted")
  func failedTestDetails() async {
    let stream = Stream()
    
    var configuration = Configuration()
    let eventRecorder = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }
    
    // Run tests with failures
    await runTest(for: FailingTestSuite.self, configuration: configuration)
    
    let buffer = stream.buffer.rawValue
    
    // Verify failure details section is generated
    #expect(buffer.contains("FAILED TEST DETAILS"))
    
    // Should show test hierarchy in failure details
    #expect(buffer.contains("FailingTestSuite"))
  }

  @Test("Test statistics are correctly calculated")
  func testStatisticsCalculation() async {
    let stream = Stream()
    
    var configuration = Configuration()
    let eventRecorder = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }
    
    // Run mixed passing and failing tests
    await runTest(for: MixedTestSuite.self, configuration: configuration)
    
    let buffer = stream.buffer.rawValue
    
    // Verify that statistics are correctly calculated and displayed
    #expect(buffer.contains("completed"))
    #expect(buffer.contains("pass:") || buffer.contains("fail:"))
  }

  @Test("Duration formatting is consistent")
  func durationFormatting() async {
    let stream = Stream()
    
    var configuration = Configuration()
    let eventRecorder = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }
    
    // Run a simple test to generate timing
    await Test(name: "Timed Test") {
      #expect(Bool(true))
    }.run(configuration: configuration)
    
    let buffer = stream.buffer.rawValue
    
    // Should not crash and should generate some output with timing
    #expect(!buffer.isEmpty)
    #expect(buffer.contains("s")) // Duration formatting should include 's' suffix
  }

  @Test("Event consolidation works correctly")
  func eventConsolidation() async {
    let stream = Stream()
    
    var configuration = Configuration()
    let eventRecorder = Event.AdvancedConsoleOutputRecorder<ABI.HighestVersion>(writingUsing: stream.write)
    configuration.eventHandler = { event, context in
      eventRecorder.record(event, in: context)
    }
    
    // Run tests to verify the consolidated data structure works
    await runTest(for: SimpleTestSuite.self, configuration: configuration)
    
    let buffer = stream.buffer.rawValue
    
    // Basic verification that the recorder processes events without crashing
    #expect(!buffer.isEmpty)
    #expect(buffer.contains("HIERARCHICAL TEST RESULTS"))
  }
}

// MARK: - Test Suites for Testing

@Suite(.hidden)
struct HierarchicalTestSuite {
  @Test(.hidden)
  func passingTest() {
    #expect(Bool(true))
  }
  
  @Test(.hidden)
  func anotherPassingTest() {
    #expect(1 + 1 == 2)
  }
  
  @Suite(.hidden)
  struct NestedSuite {
    @Test(.hidden)
    func nestedTest() {
      #expect("hello".count == 5)
    }
  }
}

@Suite(.hidden)
struct FailingTestSuite {
  @Test(.hidden)
  func failingTest() {
    #expect(Bool(false), "This test is designed to fail")
  }
  
  @Test(.hidden)
  func passingTest() {
    #expect(Bool(true))
  }
}

@Suite(.hidden)
struct MixedTestSuite {
  @Test(.hidden)
  func test1() {
    #expect(Bool(true))
  }
  
  @Test(.hidden)
  func test2() {
    #expect(Bool(false), "Intentional failure")
  }
  
  @Test(.hidden)
  func test3() {
    #expect(1 == 1)
  }
}

@Suite(.hidden)
struct SimpleTestSuite {
  @Test(.hidden)
  func simpleTest() {
    #expect(Bool(true))
  }
} 
#endif
