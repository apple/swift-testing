//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for Swift project authors
//

extension Tag {
  /// An enumeration describing colors that can be applied to tests' tags.
  ///
  /// ## See Also
  ///
  /// - <doc:categorizing-tests-and-customizing-their-appearance>
  @_spi(Experimental)
  public struct Color: Sendable {
    /// The red component of the color.
    ///
    /// This property is not part of the public interface of the testing
    /// library as we may wish to support non-RGB color spaces in the future.
    var redComponent: UInt8

    /// The green component of the color.
    ///
    /// This property is not part of the public interface of the testing
    /// library as we may wish to support non-RGB color spaces in the future.
    var greenComponent: UInt8

    /// The blue component of the color.
    ///
    /// This property is not part of the public interface of the testing
    /// library as we may wish to support non-RGB color spaces in the future.
    var blueComponent: UInt8

    /// The hue, saturation, and value (or brightness) components of the color.
    ///
    /// This property is not part of the public interface of the testing
    /// library as we may wish to support non-RGB color spaces in the future.
    var hsvComponents: (hue: Float32, saturation: Float32, value: Float32) {
      // Adapted from the algorithms at https://en.wikipedia.org/wiki/HSL_and_HSV
      // including variable names.
      let r = Float32(redComponent) / 255.0
      let g = Float32(greenComponent) / 255.0
      let b = Float32(blueComponent) / 255.0
      let M = max(max(r, g), b)
      let m = min(min(r, g), b)
      let C = M - m

      var H: Float32 = 0.0
      if C > 0.0 {
        if M == r {
          H = (g - b) / C
        } else if M == g {
          H = ((b - r) / C) + 2.0
        } else if M == b {
          H = ((r - g) / C) + 4.0
        }
        H = H / 6.0
      }
      let V: Float32 = M
      var Sv: Float32 = 0.0
      if V > 0.0 {
        Sv = C / V
      }

      return (H, Sv, V)
    }

    /// The color red.
    public static var red: Self { .rgb(255, 0, 0) }

    /// The color orange.
    public static var orange: Self { .rgb(255, 128, 0) }

    /// The color yellow.
    public static var yellow: Self { .rgb(255, 255, 0) }

    /// The color green.
    public static var green: Self { .rgb(0, 255, 0) }

    /// The color blue.
    public static var blue: Self { .rgb(0, 0, 255) }

    /// The color purple.
    public static var purple: Self { .rgb(192, 0, 224) }

    /// Get an instance of this type representing a custom color in the RGB
    /// color space.
    ///
    /// - Parameters:
    ///   - redComponent: The red component of the color.
    ///   - greenComponent: The green component of the color.
    ///   - blueComponent: The blue component of the color.
    ///
    /// - Returns: An instance of this type representing the specified color.
    ///
    /// If a tag with an RGB color is output to a terminal that does not support
    /// 256-color (or better) output, the color will not be displayed.
    public static func rgb(_ redComponent: UInt8, _ greenComponent: UInt8, _ blueComponent: UInt8) -> Self {
      self.init(redComponent: redComponent, greenComponent: greenComponent, blueComponent: blueComponent)
    }
  }
}

// MARK: - Equatable, Hashable

extension Tag.Color: Equatable, Hashable {}

// MARK: - Comparable

extension Tag.Color: Comparable {
  public static func <(lhs: Self, rhs: Self) -> Bool {
    // Compare by hue first as it will generally match human expectations for
    // color ordering. Comparing by saturation before value is arbitrary.
    let lhsHSV = lhs.hsvComponents
    let rhsHSV = rhs.hsvComponents
    if lhsHSV.hue != rhsHSV.hue {
      return lhsHSV.hue < rhsHSV.hue
    }
    if lhsHSV.saturation != rhsHSV.saturation {
      return lhsHSV.saturation < rhsHSV.saturation
    }
    return lhsHSV.value < rhsHSV.value
  }
}

// MARK: - Comparable

extension Tag.Color: Decodable {
  public init(from decoder: any Decoder) throws {
    let stringValue = try String(from: decoder)
    switch stringValue {
    case "red":
      self = .red
    case "orange":
      self = .orange
    case "yellow":
      self = .yellow
    case "green":
      self = .green
    case "blue":
      self = .blue
    case "purple":
      self = .purple
    case _ where stringValue.count == 7 && stringValue.first == "#":
      guard let rgbValue = UInt32(stringValue.dropFirst(), radix: 16) else {
        fallthrough
      }
      self = .rgb(
        UInt8((rgbValue & 0x00FF0000) >> 16),
        UInt8((rgbValue & 0x0000FF00) >> 8),
        UInt8((rgbValue & 0x000000FF) >> 0)
      )
    default:
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unsupported tag color constant \"\(stringValue)\"."
        )
      )
    }
  }
}
