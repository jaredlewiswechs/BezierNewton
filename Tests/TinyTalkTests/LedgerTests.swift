// LedgerTests.swift — Tests for the append-only ledger

import XCTest
@testable import TinyTalk

final class LedgerTests: XCTestCase {

    func testLedgerAppendsEntries() {
        let ledger = Ledger()
        XCTAssertEqual(ledger.count, 0)

        let cp = ControlPoints.linear(
            from: StateVector(0.0),
            to: StateVector(1.0)
        )

        ledger.append(
            controlPoints: cp,
            lawNames: ["test law"],
            verdict: .fin,
            forgeName: "test forge"
        )

        XCTAssertEqual(ledger.count, 1)
        XCTAssertEqual(ledger[0].forgeName, "test forge")
        XCTAssertTrue(ledger[0].verdict.isCommit)
    }

    func testLedgerPreservesOrder() {
        let ledger = Ledger()

        for i in 0..<5 {
            let cp = ControlPoints.linear(
                from: StateVector(Double(i)),
                to: StateVector(Double(i + 1))
            )
            ledger.append(
                controlPoints: cp,
                lawNames: ["law"],
                verdict: .fin,
                forgeName: "forge_\(i)"
            )
        }

        XCTAssertEqual(ledger.count, 5)
        for i in 0..<5 {
            XCTAssertEqual(ledger[i].forgeName, "forge_\(i)")
        }
    }

    func testLedgerHashesAreUnique() {
        let ledger = Ledger()
        let cp = ControlPoints.linear(
            from: StateVector(0.0),
            to: StateVector(1.0)
        )

        ledger.append(controlPoints: cp, lawNames: ["a"], verdict: .fin)
        ledger.append(controlPoints: cp, lawNames: ["a"], verdict: .fin)

        // Even identical content should get different hashes due to index
        XCTAssertNotEqual(ledger[0].hash, ledger[1].hash)
    }

    func testLedgerFiltersByVerdict() {
        let ledger = Ledger()
        let cp = ControlPoints.linear(from: StateVector(0.0), to: StateVector(1.0))

        ledger.append(controlPoints: cp, lawNames: ["a"], verdict: .fin)
        let witness = Witness(
            lawIndex: 0,
            lawName: "test",
            time: 0.5,
            state: StateVector(0.5),
            repair: nil,
            reason: "test rejection"
        )
        ledger.append(controlPoints: cp, lawNames: ["a"], verdict: .finfr(witness))
        ledger.append(controlPoints: cp, lawNames: ["a"], verdict: .fin)

        XCTAssertEqual(ledger.commits.count, 2)
        XCTAssertEqual(ledger.rejections.count, 1)
    }

    func testLedgerLawVersion() {
        let ledger = Ledger()
        XCTAssertEqual(ledger.lawVersion, 1)

        let cp = ControlPoints.linear(from: StateVector(0.0), to: StateVector(1.0))
        ledger.append(controlPoints: cp, lawNames: ["a"], verdict: .fin)
        XCTAssertEqual(ledger[0].lawVersion, 1)

        ledger.bumpLawVersion()
        XCTAssertEqual(ledger.lawVersion, 2)

        ledger.append(controlPoints: cp, lawNames: ["a", "b"], verdict: .fin)
        XCTAssertEqual(ledger[1].lawVersion, 2)
    }

    func testLedgerFiltersByForge() {
        let ledger = Ledger()
        let cp = ControlPoints.linear(from: StateVector(0.0), to: StateVector(1.0))

        ledger.append(controlPoints: cp, lawNames: ["a"], verdict: .fin, forgeName: "submit")
        ledger.append(controlPoints: cp, lawNames: ["a"], verdict: .fin, forgeName: "approve")
        ledger.append(controlPoints: cp, lawNames: ["a"], verdict: .fin, forgeName: "submit")

        XCTAssertEqual(ledger.entries(forForge: "submit").count, 2)
        XCTAssertEqual(ledger.entries(forForge: "approve").count, 1)
        XCTAssertEqual(ledger.entries(forForge: "pay").count, 0)
    }
}
