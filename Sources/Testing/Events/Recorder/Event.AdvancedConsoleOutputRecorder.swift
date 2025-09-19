//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension Event {
  /// An experimental console output recorder that provides enhanced test result
  /// display capabilities.
  ///
  /// This recorder is currently experimental and must be enabled via the
  /// `SWT_ENABLE_EXPERIMENTAL_CONSOLE_OUTPUT` environment variable.
  struct AdvancedConsoleOutputRecorder<V: ABI.Version>: Sendable {
    /// Configuration for box-drawing character rendering strategy.
    enum BoxDrawingMode: Sendable {
      /// Use Unicode box-drawing characters (┌─, ├─, ╰─, │).
      case unicode
      /// Use Windows Code Page 437 box-drawing characters (┌─, ├─, └─, │).
      case windows437
      /// Use ASCII fallback characters (--, |-, `-, |).
      case ascii
    }
    
    /// Configuration options for the advanced console output recorder.
    struct Options: Sendable {
      /// Base console output recorder options to inherit from.
      var base: Event.ConsoleOutputRecorder.Options
      
      /// Box-drawing character mode override.
      /// 
      /// When `nil` (default), the mode is automatically determined based on platform:
      /// - macOS/Linux: Unicode if ANSI enabled, otherwise ASCII
      /// - Windows: Code Page 437 if ANSI enabled, otherwise ASCII
      /// 
      /// Set to a specific mode to override the automatic selection.
      var boxDrawingMode: BoxDrawingMode?
      
      init() {
        self.base = Event.ConsoleOutputRecorder.Options()
        self.boxDrawingMode = nil // Use automatic selection
      }
    }
    
    /// Context for storing data across events during test execution.
    private struct _Context: Sendable {
      /// Storage for test information, keyed by test ID string value.
      /// This is needed because ABI.EncodedEvent doesn't contain full test context.
      var testStorage: [String: ABI.EncodedTest<V>] = [:]
      
      /// Hierarchical test tree structure using Graph for efficient operations.
      /// Key path represents the hierarchy (e.g., ["TestingTests", "ClockAPITests", "testMethod"])
      /// Value contains the test node data for that specific node.
      var testTree: Graph<String, _HierarchyNode?> = Graph()
      
      /// Consolidated test data for each test, keyed by test ID string.
      /// Contains all runtime information gathered during test execution.
      var testData: [String: _TestData] = [:]
      
      /// The instant when the test run was started.
      /// Used to calculate total run duration.
      var runStartTime: ABI.EncodedInstant<V>?
      
      /// The instant when the test run was completed.
      /// Used to calculate total run duration.
      var runEndTime: ABI.EncodedInstant<V>?
      
      /// The number of tests that passed during this run.
      var totalPassed: Int = 0
      
      /// The number of tests that failed during this run.
      var totalFailed: Int = 0
      
      /// The number of tests that were skipped during this run.
      var totalSkipped: Int = 0
    }
    
    /// Consolidated data for a single test, combining result, timing, and issues.
    private struct _TestData: Sendable {
      /// The final result of the test execution (passed, failed, or skipped).
      /// This is determined after all events for the test have been processed.
      var result: _TestResult?
      
      /// The instant when the test started executing.
      /// Used to calculate individual test duration.
      var startTime: ABI.EncodedInstant<V>?
      
      /// The instant when the test finished executing.
      /// Used to calculate individual test duration.
      var endTime: ABI.EncodedInstant<V>?
      
      /// All issues recorded during the test execution.
      /// Includes failures, warnings, and other diagnostic information.
      var issues: [ABI.EncodedIssue<V>] = []
      
      /// Detailed messages for each issue, preserving the order and association.
      /// Each inner array contains all messages for a single issue.
      var issueMessages: [[ABI.EncodedMessage<V>]] = []
    }
    
    /// Represents a node in the test hierarchy tree.
    /// Graph handles the parent-child relationships, so this only stores node-specific data.
    private struct _HierarchyNode: Sendable {
      /// The unique identifier for this test or test suite.
      let testID: String
      
      /// The base name of the test or suite without display formatting.
      let name: String
      
      /// The human-readable display name for the test or suite, if different from name.
      let displayName: String?
      
      /// Whether this node represents a test suite (true) or individual test (false).
      let isSuite: Bool
      
      init(testID: String, name: String, displayName: String?, isSuite: Bool) {
        self.testID = testID
        self.name = name
        self.displayName = displayName
        self.isSuite = isSuite
      }
    }
    
    /// Represents the result of a test execution.
    private enum _TestResult: Sendable {
      /// The test executed successfully without any failures.
      case passed
      
      /// The test failed due to one or more assertion failures or errors.
      case failed
      
      /// The test was skipped and did not execute.
      case skipped
    }
    
    /// The options for this recorder.
    let options: Options
    
    /// The write function for this recorder.
    let write: @Sendable (String) -> Void
    
    /// The fallback console recorder for standard output.
    private let _fallbackRecorder: Event.ConsoleOutputRecorder
    
    /// Context storage for test information and results.
    private let _context: Locked<_Context>
    
    /// Human-readable output recorder for generating messages.
    private let _humanReadableRecorder: Event.HumanReadableOutputRecorder
    
    /// Initialize the advanced console output recorder.
    ///
    /// - Parameters:
    ///   - options: Configuration options for the recorder.
    ///   - write: A closure that writes output to its destination.
    init(options: Options = Options(), writingUsing write: @escaping @Sendable (String) -> Void) {
      self.options = options
      self.write = write
      self._fallbackRecorder = Event.ConsoleOutputRecorder(options: options.base, writingUsing: write)
      self._context = Locked(rawValue: _Context())
      self._humanReadableRecorder = Event.HumanReadableOutputRecorder()
    }
  }
}

// MARK: - 3-Tiered Fallback Support

extension Event.AdvancedConsoleOutputRecorder {
  /// Determine the appropriate box-drawing mode based on platform and configuration.
  private var _boxDrawingMode: BoxDrawingMode {
    // Use explicit override if provided
    if let explicitMode = options.boxDrawingMode {
      return explicitMode
    }
    
    // Otherwise, use platform-appropriate defaults
#if os(Windows)
    // On Windows, prefer Code Page 437 characters if ANSI is enabled, otherwise ASCII
    return options.base.useANSIEscapeCodes ? .windows437 : .ascii
#else
    // On macOS/Linux, prefer Unicode if ANSI is enabled, otherwise ASCII
    return options.base.useANSIEscapeCodes ? .unicode : .ascii
#endif
  }
  
  /// Get the appropriate tree drawing character with 3-tiered fallback.
  ///
  /// Implements the fallback strategy:
  /// 1. Default (macOS/Linux): Unicode characters (┌─, ├─, ╰─, │)
  /// 2. Windows fallback: Code Page 437 characters (┌─, ├─, └─, │) 
  /// 3. Final fallback: ASCII characters (--, |-, `-, |)
  ///
  /// - Parameters:
  ///   - unicode: The Unicode box-drawing character to use.
  ///   - windows437: The Windows Code Page 437 character to use.
  ///   - ascii: The ASCII fallback character(s) to use.
  ///
  /// - Returns: The appropriate character based on platform and terminal capabilities.
  private func _treeCharacter(unicode: String, windows437: String, ascii: String) -> String {
    switch _boxDrawingMode {
    case .unicode:
      return unicode
    case .windows437:
      return windows437
    case .ascii:
      return ascii
    }
  }
  
  /// Get the tree branch character (├─).
  private var _treeBranch: String {
    _treeCharacter(unicode: "├─ ", windows437: "├─ ", ascii: "|- ")
  }
  
  /// Get the tree last branch character (╰─ or └─).
  private var _treeLastBranch: String {
    _treeCharacter(unicode: "╰─ ", windows437: "└─ ", ascii: "`- ")
  }
  
  /// Get the tree vertical line character (│).
  private var _treeVertical: String {
    _treeCharacter(unicode: "│", windows437: "│", ascii: "|")
  }
}

extension Event.AdvancedConsoleOutputRecorder {
  /// Record an event and its context.
  ///
  /// - Parameters:
  ///   - event: The event to record.
  ///   - eventContext: Contextual information about the event.
  public func record(_ event: borrowing Event, in eventContext: borrowing Event.Context) {
    // Extract values before entering lock to avoid borrowing issues
    let eventKind = event.kind
    let testValue = eventContext.test
    
    // Handle test discovery for hierarchy building
    if case .testDiscovered = eventKind, let test = testValue {
      let encodedTest = ABI.EncodedTest<V>(encoding: test)
      
      _context.withLock { context in
        _buildTestHierarchy(encodedTest, in: &context)
      }
    }
    
    // Generate detailed messages using HumanReadableOutputRecorder
    let messages = _humanReadableRecorder.record(event, in: eventContext)
    
    // Convert Event to ABI.EncodedEvent for processing (if needed)
    if let encodedEvent = ABI.EncodedEvent<V>(encoding: event, in: eventContext, messages: messages) {
      _processABIEvent(encodedEvent)
    }
    
    // Only output specific messages during the run, suppress most standard output
    // The hierarchical summary will be shown at the end
    switch eventKind {
    case .runStarted:
      let symbol = Event.Symbol.default.stringValue(options: _fallbackRecorder.options)
      write("\(symbol) Test run started.\n")
      
    case .runEnded:
      // The hierarchical summary is generated in _processABIEvent for runEnded
      break
      
    default:
      // Suppress other standard messages to avoid duplicate output
      // The hierarchy will show all the details at the end
      break
    }
  }
  
  /// Build the test hierarchy from discovered tests.
  ///
  /// - Parameters:
  ///   - encodedTest: The test to add to the hierarchy.
  ///   - context: The mutable context to update.
  private func _buildTestHierarchy(_ encodedTest: ABI.EncodedTest<V>, in context: inout _Context) {
    let testID = encodedTest.id.stringValue
    let isSuite = encodedTest.kind == .suite
    
    // Create hierarchy node
    let hierarchyNode = _HierarchyNode(
      testID: testID,
      name: encodedTest.name,
      displayName: encodedTest.displayName,
      isSuite: isSuite
    )
    
    // Parse the test ID to extract the key path for Graph
    let keyPath = _parseTestIDToKeyPath(testID)
    
    // Insert the node into the Graph at the appropriate key path
    context.testTree[keyPath] = hierarchyNode
    
    // Create intermediate nodes (modules and suites) if they don't exist
    for i in 1..<keyPath.count {
      let intermediateKeyPath = Array(keyPath.prefix(i))
      if context.testTree[intermediateKeyPath] == nil {
        // Create intermediate node
        let intermediateName = intermediateKeyPath.last ?? ""
        let intermediateNode = _HierarchyNode(
          testID: intermediateKeyPath.joined(separator: "."),
          name: intermediateName,
          displayName: intermediateName,
          isSuite: true
        )
        context.testTree[intermediateKeyPath] = intermediateNode
      }
    }

  }
  
  /// Parse a test ID into a key path suitable for Graph insertion.
  /// Uses existing Test.ID infrastructure and backtick-aware parsing.
  ///
  /// Examples:
  /// - "TestingTests.ClockAPITests/testMethod()" -> ["TestingTests", "ClockAPITests", "testMethod()"]
  /// - "TestingTests" -> ["TestingTests"]
  ///
  /// - Parameters:
  ///   - testID: The test ID to parse.
  /// - Returns: An array of key path components.
  private func _parseTestIDToKeyPath(_ testID: String) -> [String] {
    // Use backtick-aware split for proper handling of raw identifiers
    let components = rawIdentifierAwareSplit(testID, separator: "/").map(String.init)
    var logicalPath: [String] = []
    
    for component in components {
      // Skip source location components (filename should be the last component)
      if component.hasSuffix(".swift:") {
        break
      }
      logicalPath.append(component)
    }
    
    // Convert the first component from dot notation to separate components
    // e.g., "TestingTests.ClockAPITests" -> ["TestingTests", "ClockAPITests"]
    var keyPath: [String] = []
    
    if let firstComponent = logicalPath.first {
      let moduleParts = rawIdentifierAwareSplit(firstComponent, separator: ".").map(String.init)
      keyPath.append(contentsOf: moduleParts)
      
      // Add any additional path components (for nested suites)
      keyPath.append(contentsOf: logicalPath.dropFirst())
    }
    
    return keyPath.isEmpty ? [testID] : keyPath
  }
  
  /// Extract all root nodes (module-level nodes) from the Graph.
  ///
  /// - Parameters:
  ///   - testTree: The Graph to extract root nodes from.
  /// - Returns: Array of key paths for root nodes (modules).
  private func _rootNodes(from testTree: Graph<String, _HierarchyNode?>) -> [[String]] {
    var rootNodes: [[String]] = []
    var moduleNames: Set<String> = []
    
    // Find all unique module names (first component of key paths)
    testTree.forEach { keyPath, node in
      if node != nil && !keyPath.isEmpty {
        let moduleName = keyPath[0]
        moduleNames.insert(moduleName)
      }
    }
    
    // Convert module names to single-component key paths
    for moduleName in moduleNames.sorted() {
      rootNodes.append([moduleName])
    }
    
    return rootNodes
  }
  
  /// Find a hierarchy node from a test ID by searching the Graph.
  ///
  /// - Parameters:
  ///   - testID: The test ID to search for.
  ///   - testTree: The Graph to search in.
  /// - Returns: The hierarchy node if found.
  private func _nodeFromTestID(_ testID: String, in testTree: Graph<String, _HierarchyNode?>) -> _HierarchyNode? {
    var foundNode: _HierarchyNode?
    
    testTree.forEach { keyPath, node in
      if node?.testID == testID {
        foundNode = node
      }
    }
    
    return foundNode
  }
  
  /// Find all child key paths for a given parent key path in the Graph.
  ///
  /// - Parameters:
  ///   - parentKeyPath: The parent key path.
  ///   - testTree: The Graph to search in.
  /// - Returns: Array of child key paths sorted alphabetically.
  private func _childKeyPaths(for parentKeyPath: [String], in testTree: Graph<String, _HierarchyNode?>) -> [[String]] {
    var childKeyPaths: [[String]] = []
    
    testTree.forEach { keyPath, node in
      if keyPath.count == parentKeyPath.count + 1 &&
         keyPath.prefix(parentKeyPath.count).elementsEqual(parentKeyPath) &&
         node != nil {
        childKeyPaths.append(keyPath)
      }
    }
    
    return childKeyPaths.sorted { $0.last ?? "" < $1.last ?? "" }
  }
  
  /// Find the key path for a given test ID in the Graph.
  ///
  /// - Parameters:
  ///   - testID: The test ID to search for.
  ///   - testTree: The Graph to search in.
  /// - Returns: The key path if found, nil otherwise.
  private func _findKeyPathForTestID(_ testID: String, in testTree: Graph<String, _HierarchyNode?>) -> [String]? {
    var foundKeyPath: [String]?
    
    testTree.forEach { keyPath, node in
      if node?.testID == testID {
        foundKeyPath = keyPath
      }
    }
    
    return foundKeyPath
  }
  
  /// Process an ABI.EncodedEvent for advanced console output.
  ///
  /// This implements the enhanced console logic for hierarchical display and failure summary.
  ///
  /// - Parameters:
  ///   - encodedEvent: The ABI-encoded event to process.
  private func _processABIEvent(_ encodedEvent: ABI.EncodedEvent<V>) {
    _context.withLock { context in
      switch encodedEvent.kind {
      case .runStarted:
        context.runStartTime = encodedEvent.instant
        
      case .testStarted:
        // Track test start time
        if let testID = encodedEvent.testID?.stringValue {
          var testData = context.testData[testID] ?? _TestData()
          testData.startTime = encodedEvent.instant
          context.testData[testID] = testData
        }
        
      case .issueRecorded:
        // Record issues for failure summary
        if let testID = encodedEvent.testID?.stringValue,
           let issue = encodedEvent.issue {
          var testData = context.testData[testID] ?? _TestData()
          testData.issues.append(issue)
          testData.issueMessages.append(encodedEvent.messages)
          context.testData[testID] = testData
        }
        
      case .testEnded:
        // Track test end time and determine result
        if let testID = encodedEvent.testID?.stringValue {
          var testData = context.testData[testID] ?? _TestData()
          testData.endTime = encodedEvent.instant
          
          // Determine test result based on issues
          let hasFailures = testData.issues.contains { !$0.isKnown && ($0.isFailure ?? true) }
          let result: _TestResult = hasFailures ? .failed : .passed
          testData.result = result
          context.testData[testID] = testData
          
          // Update statistics
          switch result {
          case .passed:
            context.totalPassed += 1
          case .failed:
            context.totalFailed += 1
          case .skipped:
            context.totalSkipped += 1
          }
        }
        
      case .testSkipped:
        // Mark test as skipped
        if let testID = encodedEvent.testID?.stringValue {
          var testData = context.testData[testID] ?? _TestData()
          testData.result = .skipped
          context.testData[testID] = testData
          context.totalSkipped += 1
        }
        
      case .runEnded:
        context.runEndTime = encodedEvent.instant
        // Generate hierarchical summary
        _generateHierarchicalSummary(context: context)
        
      default:
        // Handle other event types
        break
      }
    }
  }
  
  /// Generate the final hierarchical summary when the run completes.
  ///
  /// - Parameters:
  ///   - context: The context containing all hierarchy and results data.
  private func _generateHierarchicalSummary(context: _Context) {
    var output = "\n"
    
    // Hierarchical Test Results
    output += "══════════════════════════════════════ HIERARCHICAL TEST RESULTS ══════════════════════════════════════\n"
    output += "\n"
    
    // Render the test hierarchy tree using Graph
    let rootNodes = _rootNodes(from: context.testTree)
    
    if rootNodes.isEmpty {
      // Show test results as flat list if no hierarchy
      let allTests = context.testData.sorted { $0.key < $1.key }
      for (testID, testData) in allTests {
        let statusIcon = _statusIcon(for: testData.result ?? .passed)
        let testName = _nodeFromTestID(testID, in: context.testTree)?.displayName ?? _nodeFromTestID(testID, in: context.testTree)?.name ?? testID
        output += "\(statusIcon) \(testName)\n"
      }
    } else {
      // Render the test hierarchy tree
      for (index, rootKeyPath) in rootNodes.enumerated() {
        if let rootNode = context.testTree[rootKeyPath] {
          output += _renderHierarchyNode(rootNode, keyPath: rootKeyPath, context: context, prefix: "", isLast: true)
          
          // Add blank line between top-level modules (treat as separate trees)
          if index < rootNodes.count - 1 {
            output += "\n"
          }
        }
      }
    }
    
    output += "\n"
    
    // Test run summary
    let totalTests = context.totalPassed + context.totalFailed + context.totalSkipped
    
    // Calculate total run duration
    var totalDuration = ""
    if let startTime = context.runStartTime, let endTime = context.runEndTime {
      totalDuration = _formatDuration(endTime.absolute - startTime.absolute)
    }
    
    // Format: [total] tests completed in [duration] ([pass symbol] pass: [number], [failed symbol] fail: [number], ...)
    let passIcon = _statusIcon(for: .passed)
    let failIcon = _statusIcon(for: .failed) 
    let skipIcon = _statusIcon(for: .skipped)
    
    var summaryParts: [String] = []
    if context.totalPassed > 0 {
      summaryParts.append("\(passIcon) pass: \(context.totalPassed)")
    }
    if context.totalFailed > 0 {
      summaryParts.append("\(failIcon) fail: \(context.totalFailed)")
    }
    if context.totalSkipped > 0 {
      summaryParts.append("\(skipIcon) skip: \(context.totalSkipped)")
    }
    
    let summaryDetails = summaryParts.joined(separator: ", ")
    let durationText = totalDuration.isEmpty ? "" : " in \(totalDuration)"
    output += "\(totalTests) test\(totalTests == 1 ? "" : "s") completed\(durationText) (\(summaryDetails))\n"
    output += "\n"
    
    // Failed Test Details (only if there are failures)
    let failedTests = context.testData.filter { $0.value.result == .failed }
    if !failedTests.isEmpty {
      output += "══════════════════════════════════════ FAILED TEST DETAILS (\(failedTests.count)) ══════════════════════════════════════\n"
      output += "\n"
      
      // Iterate through all tests that recorded one or more failures
      for (testIndex, testEntry) in failedTests.enumerated() {
        let (testID, testData) = testEntry
        let testNumber = testIndex + 1
        let totalFailedTests = failedTests.count
        
        // Get the fully qualified test name by traversing up the hierarchy
        let fullyQualifiedName = _getFullyQualifiedTestNameWithFile(testID: testID, context: context)
        
        let failureIcon = _statusIcon(for: .failed)
        output += "\(failureIcon) \(fullyQualifiedName)\n"
        
        // Show detailed issue information with enhanced formatting
        if !testData.issues.isEmpty {
          for (issueIndex, issue) in testData.issues.enumerated() {
            // 1. Error Message - Get detailed error description
            let issueDescription = _formatDetailedIssueDescription(issue, issueIndex: issueIndex, testData: testData)
            
            if !issueDescription.isEmpty {
              let errorLines = issueDescription.split(separator: "\n", omittingEmptySubsequences: false)
              for line in errorLines {
                output += "  \(line)\n"
              }
            }
            
            // 2. Location
            if let sourceLocation = issue.sourceLocation {
              output += "\n"
              output += "  Location: \(sourceLocation.fileName):\(sourceLocation.line):\(sourceLocation.column)\n"
            }
            
            // 3. Statistics - Error counter in lower right
            let errorCounter = "[\(testNumber)/\(totalFailedTests)]"
            let paddingLength = max(0, 100 - errorCounter.count)
            output += "\n"
            output += "\(String(repeating: " ", count: paddingLength))\(errorCounter)\n"
            
            // Add spacing between issues (except for the last one)
            if issueIndex < testData.issues.count - 1 {
              output += "\n"
            }
          }
        }
        
        // Add spacing between tests (except for the last one)
        if testIndex < failedTests.count - 1 {
          output += "\n"
        }
      }
    }
    
    write(output)
  }
  
  /// Render a hierarchy node with proper indentation and tree drawing characters.
  ///
  /// - Parameters:
  ///   - node: The node to render.
  ///   - context: The hierarchy context.
  ///   - prefix: The prefix for indentation and tree drawing.
  ///   - isLast: Whether this is the last child at its level.
  /// - Returns: The rendered string for this node and its children.
  private func _renderHierarchyNode(_ node: _HierarchyNode, keyPath: [String], context: _Context, prefix: String, isLast: Bool) -> String {
    var output = ""
    
    if node.isSuite {
      // Suite header
      let treePrefix: String
      if prefix.isEmpty {
        // Top-level modules: no tree prefix, flush left (treat as separate trees)
        treePrefix = ""
      } else {
        // Nested suites: use standard tree characters
        treePrefix = isLast ? _treeLastBranch : _treeBranch
      }
      
      let suiteName = node.displayName ?? node.name
      output += "\(prefix)\(treePrefix)\(suiteName)\n"
      
      // Render children with updated prefix  
      let childPrefix: String
      if prefix.isEmpty {
        // Top-level modules: children start with 3 spaces (no vertical line needed)
        childPrefix = "   "
      } else {
        // Nested case: continue vertical line unless this is the last node
        childPrefix = prefix + (isLast ? "   " : "\(_treeVertical)  ")
      }
      
      let childKeyPaths = _childKeyPaths(for: keyPath, in: context.testTree)
      for (childIndex, childKeyPath) in childKeyPaths.enumerated() {
        let isLastChild = childIndex == childKeyPaths.count - 1
        if let childNode = context.testTree[childKeyPath] {
          output += _renderHierarchyNode(childNode, keyPath: childKeyPath, context: context, prefix: childPrefix, isLast: isLastChild)
          
          // Add spacing between child nodes when the next sibling is a suite
          // Continue the tree structure with vertical line
          if childIndex < childKeyPaths.count - 1 {
            // Check if the next sibling is a suite
            let nextChildKeyPath = childKeyPaths[childIndex + 1]
            if let nextChildNode = context.testTree[nextChildKeyPath], nextChildNode.isSuite {
              // Use the correct spacing prefix
              let spacingPrefix: String
              if prefix.isEmpty {
                // Top-level modules: use 3 spaces + vertical line
                spacingPrefix = "   \(_treeVertical)"
              } else {
                // Nested case: use the child prefix
                spacingPrefix = childPrefix
              }
              output += "\(spacingPrefix)\n"  // Add the vertical line continuation
            }
          }
        }
      }
    } else {
      // Test case line
      let treePrefix = isLast ? _treeLastBranch : _treeBranch
      let statusIcon = _statusIcon(for: context.testData[node.testID]?.result ?? .passed)
      let testName = node.displayName ?? node.name
      
      // Calculate duration
      var duration = ""
      if let startTime = context.testData[node.testID]?.startTime,
         let endTime = context.testData[node.testID]?.endTime {
        duration = _formatDuration(endTime.absolute - startTime.absolute)
      }
      
      // Format with right-aligned duration
      let testLine = "\(statusIcon) \(testName)"
      let fullPrefix = "\(prefix)\(treePrefix)"
      let paddedTestLine = _padWithDuration(testLine, duration: duration, existingPrefix: fullPrefix)
      output += "\(fullPrefix)\(paddedTestLine)\n"
      
      // Show concise issue summary for quick overview
      if let issues = context.testData[node.testID]?.issues, !issues.isEmpty {
        let issuePrefix = prefix + (isLast ? "   " : "\(_treeVertical)  ")
        for (issueIndex, issue) in issues.enumerated() {
          let isLastIssue = issueIndex == issues.count - 1
          let issueTreePrefix = isLastIssue ? _treeLastBranch : _treeBranch
          
          // Show "Expectation failed" with the actual error details
          let fullDescription = _formatDetailedIssueDescription(issue, issueIndex: issueIndex, testData: context.testData[node.testID]!)
          let conciseDescription = fullDescription.split(separator: "\n").first.map(String.init) ?? "Expected condition was not met"
          output += "\(issuePrefix)\(issueTreePrefix)Expectation failed: \(conciseDescription)\n"
          
          // Add concise source location
          if let sourceLocation = issue.sourceLocation {
            let locationPrefix = issuePrefix + (isLastIssue ? "   " : "\(_treeVertical)  ")
            output += "\(locationPrefix)at \(sourceLocation.fileName):\(sourceLocation.line)\n"
          }
        }
      }
    }
    
    return output
  }
  
  /// Format a detailed description of an issue for the Failed Test Details section.
  ///
  /// - Parameters:
  ///   - issue: The encoded issue to format.
  ///   - issueIndex: The index of the issue in the testData.issues array.
  ///   - testData: The test data containing the stored messages.
  /// - Returns: A detailed description of what failed.
  private func _formatDetailedIssueDescription(_ issue: ABI.EncodedIssue<V>, issueIndex: Int, testData: _TestData) -> String {
    // Get the corresponding messages for this issue
    guard issueIndex < testData.issueMessages.count else {
      // Fallback to error description if available
      if let error = issue._error {
        return error.description
      }
      return "Issue recorded"
    }
    
    let messages = testData.issueMessages[issueIndex]
    
    // Look for detailed messages (difference, details) that contain the actual failure information
    var detailedMessages: [String] = []
    
    for message in messages {
      switch message.symbol {
      case .difference, .details:
        // These contain the detailed expectation failure information
        detailedMessages.append(message.text)
      case .fail:
        // Primary failure message - use if no detailed messages available
        if detailedMessages.isEmpty {
          detailedMessages.append(message.text)
        }
      default:
        break
      }
    }
    
    if !detailedMessages.isEmpty {
      let fullMessage = detailedMessages.joined(separator: "\n")
      // Truncate very long messages to prevent layout issues
      if fullMessage.count > 200 {
        let truncated = String(fullMessage.prefix(200))
        return truncated + "..."
      }
      return fullMessage
    }
    
    // Final fallback
    if let error = issue._error {
      let errorDesc = error.description
      // Truncate very long error descriptions
      if errorDesc.count > 200 {
        return String(errorDesc.prefix(200)) + "..."
      }
      return errorDesc
    }
    return "Issue recorded"
  }
  
  /// Determine the status icon for a test result.
  ///
  /// - Parameters:
  ///   - result: The test result.
  /// - Returns: The appropriate symbol string.
  private func _statusIcon(for result: _TestResult) -> String {
    switch result {
    case .passed:
      return Event.Symbol.pass(knownIssueCount: 0).stringValue(options: options.base)
    case .failed:
      return Event.Symbol.fail.stringValue(options: options.base)
    case .skipped:
      return Event.Symbol.skip.stringValue(options: options.base)
    }
  }
  
  /// Format a duration in seconds with exactly 2 decimal places.
  ///
  /// - Parameter duration: The duration to format.
  /// - Returns: A formatted duration string (e.g., "1.80s", "0.05s").
  private func _formatDuration(_ duration: Double) -> String {
    // Always format to exactly 2 decimal places
    let wholePart = Int(duration)
    let fractionalPart = Int((duration - Double(wholePart)) * 100 + 0.5) // Round to nearest hundredth
    
    // Handle rounding overflow (e.g., 0.999 -> 1.00)
    if fractionalPart >= 100 {
      return "\(wholePart + 1).00s"
    } else {
      let fractionalString = fractionalPart < 10 ? "0\(fractionalPart)" : "\(fractionalPart)"
      return "\(wholePart).\(fractionalString)s"
    }
  }
  
  /// Pad a test line with right-aligned duration.
  ///
  /// - Parameters:
  ///   - testLine: The test line to pad.
  ///   - duration: The duration string.
  ///   - existingPrefix: Any prefix that will be added before this line.
  /// - Returns: The padded test line with right-aligned duration.
  private func _padWithDuration(_ testLine: String, duration: String, existingPrefix: String = "") -> String {
    if duration.isEmpty {
      return testLine
    }
    
    // Get terminal width dynamically, fall back to 120 if unavailable
    let targetWidth = _terminalWidth()
    let rightPart = "(\(duration))"
    
    // Calculate visible character count (excluding ANSI escape codes)
    let visiblePrefixLength = _visibleCharacterCount(existingPrefix)
    let visibleLeftLength = _visibleCharacterCount(testLine)
    let totalRightLength = rightPart.count
    
    // Ensure minimum spacing between content and duration
    let minimumSpacing = 3
    let totalUsedWidth = visiblePrefixLength + visibleLeftLength + totalRightLength + minimumSpacing
    
    if totalUsedWidth < targetWidth {
      let paddingLength = targetWidth - visiblePrefixLength - visibleLeftLength - totalRightLength
      return "\(testLine)\(String(repeating: " ", count: paddingLength))\(rightPart)"
    } else {
      return "\(testLine) \(rightPart)"
    }
  }
  
  /// Determine the current terminal width, with fallback to reasonable default.
  ///
  /// - Returns: Terminal width in characters, defaults to 120 if unavailable.
  private func _terminalWidth() -> Int {
    // Try to get terminal width from environment variable
    if let columnsEnv = Environment.variable(named: "COLUMNS"),
       let columns = Int(columnsEnv), columns > 0 {
      return columns
    }
    
    // Fallback to a reasonable default width
    // Modern terminals are typically 120+ characters wide
    return 120
  }
  
  /// Calculate the visible character count, excluding ANSI escape sequences.
  ///
  /// - Parameters:
  ///   - string: The string to count visible characters in.
  /// - Returns: The number of visible characters.
  private func _visibleCharacterCount(_ string: String) -> Int {
    var visibleCount = 0
    var inEscapeSequence = false
    var i = string.startIndex
    
    while i < string.endIndex {
      let char = string[i]
      
      if char == "\u{1B}" { // ESC character
        inEscapeSequence = true
      } else if inEscapeSequence && (char == "m" || char == "K") {
        // End of ANSI escape sequence
        inEscapeSequence = false
      } else if !inEscapeSequence {
        visibleCount += 1
      }
      
      i = string.index(after: i)
    }
    
    return visibleCount
  }
  
  /// Get the fully qualified test name for a given test ID.
  ///
  /// This function traverses the hierarchy to build the full test name.
  ///
  /// - Parameters:
  ///   - testID: The ID of the test.
  ///   - context: The context containing the test hierarchy.
  /// - Returns: The fully qualified test name.
  private func _getFullyQualifiedTestName(testID: String, context: _Context) -> String {
    guard let keyPath = _findKeyPathForTestID(testID, in: context.testTree) else { return testID }
    
    var nameParts: [String] = []
    
    // Build the hierarchy path by traversing from root to leaf
    for i in 1...keyPath.count {
      let currentKeyPath = Array(keyPath.prefix(i))
      if let node = context.testTree[currentKeyPath] {
        let displayName = node.displayName ?? node.name
        nameParts.append(displayName)
      }
    }
    
    return nameParts.joined(separator: "/")
  }

  /// Get the fully qualified test name for a given test ID, including the file name.
  ///
  /// This function traverses the hierarchy to build the full test name in the format:
  /// ModuleName/FileName/"SuiteName"/"TestName"
  ///
  /// - Parameters:
  ///   - testID: The ID of the test.
  ///   - context: The context containing the test hierarchy.
  /// - Returns: The fully qualified test name with file name included.
  private func _getFullyQualifiedTestNameWithFile(testID: String, context: _Context) -> String {
    guard let keyPath = _findKeyPathForTestID(testID, in: context.testTree) else { return testID }
    
    // Get the source file name from the first issue
    var fileName = ""
    if let issues = context.testData[testID]?.issues, 
       let firstIssue = issues.first,
       let sourceLocation = firstIssue.sourceLocation {
      fileName = sourceLocation.fileName
    }
    
    var nameParts: [String] = []
    
    // Build the hierarchy path by traversing from root to leaf
    for i in 1...keyPath.count {
      let currentKeyPath = Array(keyPath.prefix(i))
      if let node = context.testTree[currentKeyPath] {
        let displayName = node.displayName ?? node.name
        
        // For non-module nodes (suites and tests), wrap in quotes
        if i > 1 {
          nameParts.append("\"\(displayName)\"")
        } else {
          // Module name - no quotes
          nameParts.append(displayName)
        }
      }
    }
    
    // Insert file name after module name if we have it
    if !fileName.isEmpty && nameParts.count > 0 {
      nameParts.insert(fileName, at: 1)
    }
    
    return nameParts.joined(separator: "/")
  }
}
