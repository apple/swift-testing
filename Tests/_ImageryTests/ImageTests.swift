import XCTest
@testable import _Imagery

final class ImageTests: XCTestCase {
  func testComparison() {
    let a = Image(unsafeBaseAddress: .init(bitPattern: 12345)!)
    let b = Image(unsafeBaseAddress: .init(bitPattern: 12345)!)
    XCTAssertTrue(a == b)
  }

  func testLookup() {
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    let sectionName = "__TEXT,__swift5_types"
#elseif os(Linux)
    let sectionName = "swift5_type_metadata"
#elseif os(Windows)
    let sectionName = ".sw5tymd"
#endif
    var foundCount = 0

    Image.forEach { image in
      // print(image.name)
      if let section = image.section(named: sectionName) {
        // print(image.name, "has", sectionName)
        XCTAssertEqual(section.name, sectionName)
        foundCount += 1
      }
    }
    XCTAssertGreaterThan(foundCount, 0, "Did not find any images with a '\(sectionName)' section")
  }

  struct SomeError: Error {}

  func testLookupWithEarlyExit() {
    let enumerated = expectation(description: "Enumerated an image")
    enumerated.expectedFulfillmentCount = 1

    XCTAssertThrowsError(
      try Image.forEach { image in
        enumerated.fulfill()
        throw SomeError()
      }
    )

    wait(for: [enumerated], timeout: 0.0)
  }

  func testMainImage() throws {
    Image.main.withUnsafePointerToBaseAddress { baseAddress in
      XCTAssertNotNil(baseAddress)
    }
  }

  func testFromUnsafeBaseAddress() {
    Image.main.withUnsafePointerToBaseAddress { baseAddress in
      let image2 = Image(unsafeBaseAddress: baseAddress)
      image2.withUnsafePointerToBaseAddress { baseAddress in
        XCTAssertNotNil(baseAddress)
      }
      XCTAssertNotNil(image2.name)
    }
  }

  func testFromAddress() {
    guard let image = Image(containing: #dsohandle) else {
      XCTFail("No image for #dsohandle")
      return
    }
    XCTAssertNotNil(image.name)
  }

  func testFromEnumeratedAddresses() {
    Image.forEach { image in
      image.withUnsafePointerToBaseAddress { baseAddress in
        guard let image2 = Image(containing: baseAddress) else {
          XCTFail("No image for baseAddress \(baseAddress)")
          return
        }
        image2.withUnsafePointerToBaseAddress { baseAddress2 in
          XCTAssertEqual(baseAddress, baseAddress2)
        }
        XCTAssertEqual(image.name, image2.name)
      }
    }
  }
}

