//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

@testable import Testing

@Suite("Cartesian Product Tests")
struct CartesianProductTests {
  /// Compute the Cartesian product of two randomly generated collections.
  ///
  /// - Returns: A tuple containing two collections and their Cartesian product.
  ///
  /// The first collection in the Cartesian product is the uppercase English
  /// Latin alphabet, shuffled. The second collection contains 100 randomly
  /// generated positive integers.
  func computeCartesianProduct() -> (c1: [Character], c2: [Int], product: CartesianProduct<[Character], [Int]>) {
    let c1 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ".shuffled()
    let c2 = (0 ..< 100).map { _ in Int.random(in: 1 ... .max ) }
    let product = cartesianProduct(c1, c2)
    return (c1, c2, product)
  }

  @Test("Count of cartesian product")
  func count() {
    // Test the size of the product is correct.
    let (c1, c2, product) = computeCartesianProduct()
    #expect(product.underestimatedCount == c1.underestimatedCount * c2.underestimatedCount)
    #expect(Array(product).count == c1.count * c2.count)
    #expect(Array(product).count == 26 * 100)
  }

  @Test("First element is correct")
  func firstElement() throws {
    // Check that the first element is correct. (This value is also tested in
    // testCompleteEquality().)
    let (c1, c2, product) = computeCartesianProduct()
    let first = try #require(product.first(where: { _ in true }))
    #expect(first.0 == c1.first)
    #expect(first.1 == c2.first)
  }

  @Test("Cartesian products compare equal")
  func completeEquality() {
    // Test that every value in a manually-computed Cartesian product is present
    // in the Cartesian product instance, and in the same order.
    let (c1, c2, product) = computeCartesianProduct()
    let possibleValues = c1.flatMap { v1 in
      c2.map { v2 in
        (v1, v2)
      }
    }

    // NOTE: we need to break out the tuple elements because tuples aren't
    // directly equatable.
    #expect(Array(product).map(\.0) == possibleValues.map(\.0))
    #expect(Array(product).map(\.1) == possibleValues.map(\.1))
  }

  @Test("Cartesian product with empty first input is empty")
  func cartesianProductWithEmptyCollection1() {
    // Test that an empty first collection produces an empty product.
    let c1 = 0 ..< 0
    let (_, c2, _) = computeCartesianProduct()
    let product = cartesianProduct(c1, c2)
    #expect(product.underestimatedCount == 0)
    #expect(Array(product).count == 0)
  }

  @Test("Cartesian product with empty second input is empty")
  func cartesianProductWithEmptyCollection2() {
    // Test that an empty second collection produces an empty product.
    let (c1, _, _) = computeCartesianProduct()
    let c2 = 0 ..< 0
    let product = cartesianProduct(c1, c2)
    #expect(product.underestimatedCount == 0)
    #expect(Array(product).count == 0)
  }

  @Test("Summing values is consistent")
  func summingCartesianProductTwice() {
    // Test that the product can be iterated twice using reduce(into:_:).
    let (_, _, product) = computeCartesianProduct()
    let sum1 = product.reduce(into: 0) { $0 &+= $1.1 }
    let sum2 = product.reduce(into: 0) { $0 &+= $1.1 }
    #expect(sum1 == sum2)
  }

  @Test("Concurrent access (summing ten times) is consistent")
  func concurrentlySummingCartesianProductTenTimes() async {
    // Test that the product can be iterated multiple times concurrently.
    let (_, _, product) = computeCartesianProduct()
    let expectedSum = product.reduce(into: 0) { $0 &+= $1.1 }
    await withTaskGroup { taskGroup in
      for _ in 0 ..< 10 {
        taskGroup.addTask {
          product.reduce(into: 0) { $0 &+= $1.1 }
        }
      }
      for await sum in taskGroup {
        #expect(expectedSum == sum)
      }
    }
  }

  @Test("CartesianProduct.underestimatedCount is clamped at .max")
  func underestimatedCountClamps() {
    // Test that underestimatedCount clamps at .max instead of overflowing.
    let product = cartesianProduct(0 ..< .max, 0 ..< .max)
    #expect(product.underestimatedCount == .max)
  }
}
