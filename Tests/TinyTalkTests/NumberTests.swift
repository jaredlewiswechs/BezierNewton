// NumberTests.swift — Tests for the Number type

import XCTest
@testable import TinyTalk

final class NumberTests: XCTestCase {

    func testIntegerLiteral() {
        let n: Number = 42
        XCTAssertEqual(n, Number(42))
    }

    func testFloatLiteral() {
        let n: Number = 3.14
        XCTAssertEqual(n.doubleValue, 3.14, accuracy: 1e-10)
    }

    func testArithmetic() {
        let a: Number = 10
        let b: Number = 3

        XCTAssertEqual(a + b, Number(13))
        XCTAssertEqual(a - b, Number(7))
        XCTAssertEqual(a * b, Number(30))
    }

    func testComparison() {
        let a: Number = 5
        let b: Number = 10

        XCTAssertTrue(a < b)
        XCTAssertTrue(b > a)
        XCTAssertTrue(a <= Number(5))
        XCTAssertTrue(a >= Number(5))
        XCTAssertFalse(a > b)
    }

    func testComparisonWithInt() {
        let n: Number = 5
        XCTAssertTrue(n > 0)
        XCTAssertTrue(n > 4)
        XCTAssertFalse(n > 5)
        XCTAssertTrue(n >= 5)
        XCTAssertTrue(n < 6)
        XCTAssertTrue(n <= 5)
    }

    func testNegation() {
        let n: Number = 5
        let neg = -n
        XCTAssertEqual(neg, Number(-5))
    }

    func testDescription() {
        let n: Number = 42
        XCTAssertEqual(n.description, "42")
    }

    func testFieldConvertible() {
        let n: Number = 3.14
        let sv = n.stateValue
        let reconstructed = Number.fromStateValue(sv)
        XCTAssertEqual(n.doubleValue, reconstructed.doubleValue, accuracy: 1e-10)
    }
}
