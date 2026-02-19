// Number.swift — TinyTalk's numeric type
// Wraps Foundation.Decimal for exact arithmetic in constraint checking.

import Foundation

/// A numeric type that handles both integers and decimals with exact arithmetic.
///
/// `Number` is one of tinyTalk's six reserved words. It wraps `Decimal` so that
/// constraint verification never suffers from floating-point rounding errors in
/// the dimensions that matter (state comparisons, threshold checks).
///
/// For Bézier interpolation (which is geometric and tolerance-based by nature),
/// the engine converts to `Double` internally.
public struct Number: Sendable {
    public var decimalValue: Decimal

    public init(_ value: Int) {
        self.decimalValue = Decimal(value)
    }

    public init(_ value: Double) {
        self.decimalValue = Decimal(value)
    }

    public init(_ value: Decimal) {
        self.decimalValue = value
    }

    public init(integerLiteral value: Int) {
        self.decimalValue = Decimal(value)
    }

    public init(floatLiteral value: Double) {
        self.decimalValue = Decimal(value)
    }

    /// Convert to Double for geometric calculations (Bézier interpolation).
    public var doubleValue: Double {
        NSDecimalNumber(decimal: decimalValue).doubleValue
    }
}

// MARK: - Expressible by literals

extension Number: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = Int
}

extension Number: ExpressibleByFloatLiteral {
    public typealias FloatLiteralType = Double
}

// MARK: - Equatable, Comparable, Hashable

extension Number: Equatable {
    public static func == (lhs: Number, rhs: Number) -> Bool {
        lhs.decimalValue == rhs.decimalValue
    }
}

extension Number: Comparable {
    public static func < (lhs: Number, rhs: Number) -> Bool {
        lhs.decimalValue < rhs.decimalValue
    }
}

extension Number: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(decimalValue)
    }
}

// MARK: - Arithmetic

extension Number {
    public static func + (lhs: Number, rhs: Number) -> Number {
        Number(lhs.decimalValue + rhs.decimalValue)
    }

    public static func - (lhs: Number, rhs: Number) -> Number {
        Number(lhs.decimalValue - rhs.decimalValue)
    }

    public static func * (lhs: Number, rhs: Number) -> Number {
        Number(lhs.decimalValue * rhs.decimalValue)
    }

    public static func / (lhs: Number, rhs: Number) -> Number {
        Number(Decimal(lhs.doubleValue / rhs.doubleValue))
    }

    public static prefix func - (value: Number) -> Number {
        Number(Decimal(0) - value.decimalValue)
    }

    public static func += (lhs: inout Number, rhs: Number) {
        lhs = lhs + rhs
    }

    public static func -= (lhs: inout Number, rhs: Number) {
        lhs = lhs - rhs
    }

    public static func *= (lhs: inout Number, rhs: Number) {
        lhs = lhs * rhs
    }

    public static func /= (lhs: inout Number, rhs: Number) {
        lhs = lhs / rhs
    }
}

// MARK: - Convenience operators with Int/Double

extension Number {
    public static func * (lhs: Double, rhs: Number) -> Number {
        Number(lhs) * rhs
    }

    public static func * (lhs: Number, rhs: Double) -> Number {
        lhs * Number(rhs)
    }

    public static func + (lhs: Number, rhs: Int) -> Number {
        lhs + Number(rhs)
    }

    public static func + (lhs: Int, rhs: Number) -> Number {
        Number(lhs) + rhs
    }

    public static func > (lhs: Number, rhs: Int) -> Bool {
        lhs > Number(rhs)
    }

    public static func < (lhs: Number, rhs: Int) -> Bool {
        lhs < Number(rhs)
    }

    public static func >= (lhs: Number, rhs: Int) -> Bool {
        lhs >= Number(rhs)
    }

    public static func <= (lhs: Number, rhs: Int) -> Bool {
        lhs <= Number(rhs)
    }
}

// MARK: - CustomStringConvertible

extension Number: CustomStringConvertible {
    public var description: String {
        "\(decimalValue)"
    }
}

// MARK: - Codable

extension Number: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.decimalValue = try container.decode(Decimal.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(decimalValue)
    }
}
