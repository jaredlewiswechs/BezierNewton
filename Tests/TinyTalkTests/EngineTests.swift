// EngineTests.swift — Tests for the Newton verification engine

import XCTest
@testable import TinyTalk

final class EngineTests: XCTestCase {

    // MARK: - State Vector

    func testStateVectorArithmetic() {
        let a = StateVector(1.0, 2.0, 3.0)
        let b = StateVector(4.0, 5.0, 6.0)

        let sum = a + b
        XCTAssertEqual(sum.components, [5.0, 7.0, 9.0])

        let diff = b - a
        XCTAssertEqual(diff.components, [3.0, 3.0, 3.0])

        let scaled = 2.0 * a
        XCTAssertEqual(scaled.components, [2.0, 4.0, 6.0])
    }

    func testStateVectorNorm() {
        let v = StateVector(3.0, 4.0)
        XCTAssertEqual(v.norm, 5.0, accuracy: 1e-10)
    }

    func testStateVectorDistance() {
        let a = StateVector(0.0, 0.0)
        let b = StateVector(3.0, 4.0)
        XCTAssertEqual(a.distance(to: b), 5.0, accuracy: 1e-10)
    }

    // MARK: - Bézier Curve Evaluation

    func testBezierEndpoints() {
        let cp = ControlPoints(
            p0: StateVector(0.0, 0.0),
            p1: StateVector(1.0, 2.0),
            p2: StateVector(3.0, 2.0),
            p3: StateVector(4.0, 0.0)
        )

        let start = cp.evaluate(at: 0.0)
        XCTAssertEqual(start.components[0], 0.0, accuracy: 1e-10)
        XCTAssertEqual(start.components[1], 0.0, accuracy: 1e-10)

        let end = cp.evaluate(at: 1.0)
        XCTAssertEqual(end.components[0], 4.0, accuracy: 1e-10)
        XCTAssertEqual(end.components[1], 0.0, accuracy: 1e-10)
    }

    func testBezierMidpoint() {
        // Linear Bézier (all collinear) should give midpoint at t=0.5
        let cp = ControlPoints.linear(
            from: StateVector(0.0, 0.0),
            to: StateVector(6.0, 6.0)
        )

        let mid = cp.evaluate(at: 0.5)
        XCTAssertEqual(mid.components[0], 3.0, accuracy: 1e-10)
        XCTAssertEqual(mid.components[1], 3.0, accuracy: 1e-10)
    }

    func testBezierDerivativeAtEndpoints() {
        // γ'(0) = 3(P1 - P0), γ'(1) = 3(P3 - P2)
        let cp = ControlPoints(
            p0: StateVector(0.0, 0.0),
            p1: StateVector(1.0, 3.0),
            p2: StateVector(2.0, -1.0),
            p3: StateVector(3.0, 0.0)
        )

        let dStart = cp.derivative(at: 0.0)
        XCTAssertEqual(dStart.components[0], 3.0, accuracy: 1e-10) // 3*(1-0)
        XCTAssertEqual(dStart.components[1], 9.0, accuracy: 1e-10) // 3*(3-0)

        let dEnd = cp.derivative(at: 1.0)
        XCTAssertEqual(dEnd.components[0], 3.0, accuracy: 1e-10)  // 3*(3-2)
        XCTAssertEqual(dEnd.components[1], 3.0, accuracy: 1e-10)  // 3*(0-(-1))
    }

    // MARK: - De Casteljau Subdivision

    func testDeCasteljauSplitPreservesCurve() {
        let cp = ControlPoints(
            p0: StateVector(0.0, 0.0),
            p1: StateVector(1.0, 3.0),
            p2: StateVector(3.0, 3.0),
            p3: StateVector(4.0, 0.0)
        )

        let (left, right) = deCasteljauSplit(cp, at: 0.5)

        // The split point should be the curve value at t=0.5
        let expected = cp.evaluate(at: 0.5)
        XCTAssertEqual(left.p3.components[0], expected.components[0], accuracy: 1e-10)
        XCTAssertEqual(left.p3.components[1], expected.components[1], accuracy: 1e-10)
        XCTAssertEqual(right.p0.components[0], expected.components[0], accuracy: 1e-10)
        XCTAssertEqual(right.p0.components[1], expected.components[1], accuracy: 1e-10)

        // Left sub-curve at t=0 should be original P0
        XCTAssertEqual(left.p0.components[0], cp.p0.components[0], accuracy: 1e-10)

        // Right sub-curve at t=1 should be original P3
        XCTAssertEqual(right.p3.components[0], cp.p3.components[0], accuracy: 1e-10)
    }

    func testDeCasteljauSubcurvesMatchOriginal() {
        let cp = ControlPoints(
            p0: StateVector(1.0, 1.0),
            p1: StateVector(2.0, 4.0),
            p2: StateVector(5.0, 4.0),
            p3: StateVector(6.0, 1.0)
        )

        let (left, right) = deCasteljauSplit(cp, at: 0.5)

        // Points on the left subcurve should match the original curve
        // Left subcurve at parameter u maps to original at t = 0.5*u
        for u in stride(from: 0.0, through: 1.0, by: 0.1) {
            let leftPoint = left.evaluate(at: u)
            let origPoint = cp.evaluate(at: 0.5 * u)
            XCTAssertEqual(leftPoint.components[0], origPoint.components[0], accuracy: 1e-8)
            XCTAssertEqual(leftPoint.components[1], origPoint.components[1], accuracy: 1e-8)
        }

        // Right subcurve at parameter u maps to original at t = 0.5 + 0.5*u
        for u in stride(from: 0.0, through: 1.0, by: 0.1) {
            let rightPoint = right.evaluate(at: u)
            let origPoint = cp.evaluate(at: 0.5 + 0.5 * u)
            XCTAssertEqual(rightPoint.components[0], origPoint.components[0], accuracy: 1e-8)
            XCTAssertEqual(rightPoint.components[1], origPoint.components[1], accuracy: 1e-8)
        }
    }

    // MARK: - Bernstein Basis

    func testBernsteinPartitionOfUnity() {
        // Sum of Bernstein basis polynomials should be 1 for all t
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            var sum = 0.0
            for i in 0...3 {
                sum += bernsteinBasis(i: i, n: 3, t: t)
            }
            XCTAssertEqual(sum, 1.0, accuracy: 1e-10)
        }
    }

    func testBernsteinNonNegativity() {
        for t in stride(from: 0.0, through: 1.0, by: 0.05) {
            for i in 0...3 {
                XCTAssertGreaterThanOrEqual(bernsteinBasis(i: i, n: 3, t: t), 0.0)
            }
        }
    }

    // MARK: - Verification Engine

    func testVerifyAdmissibleTrajectory() {
        // A trajectory entirely inside the lawful region should return fin
        let engine = NewtonEngine()

        let cp = ControlPoints.linear(
            from: StateVector(1.0, 1.0),
            to: StateVector(3.0, 3.0)
        )

        // Law: both coordinates must be positive
        let law = Law(name: "positive") { state in
            state[0] > 0 && state[1] > 0
        }

        let verdict = engine.verify(controlPoints: cp, laws: [law])
        XCTAssertTrue(verdict.isCommit)
    }

    func testVerifyInadmissibleTrajectory() {
        // A trajectory that crosses the boundary should return finfr
        let engine = NewtonEngine()

        let cp = ControlPoints.linear(
            from: StateVector(1.0, 1.0),
            to: StateVector(-1.0, -1.0)
        )

        // Law: both coordinates must be positive
        let law = Law(name: "positive") { state in
            state[0] > 0 && state[1] > 0
        }

        let verdict = engine.verify(controlPoints: cp, laws: [law])
        XCTAssertTrue(verdict.isFinfr)
        XCTAssertNotNil(verdict.witness)
        XCTAssertEqual(verdict.witness?.lawName, "positive")
    }

    func testVerifyWithConvexHullQuickAccept() {
        // When all control points are in Ω and Ω is convex, quick accept
        let engine = NewtonEngine()

        let cp = ControlPoints(
            p0: StateVector(1.0, 1.0),
            p1: StateVector(2.0, 3.0),
            p2: StateVector(4.0, 3.0),
            p3: StateVector(5.0, 1.0)
        )

        // Convex region: x > 0, y > 0, x + y < 10
        let laws = [
            Law(name: "x positive") { $0[0] > 0 },
            Law(name: "y positive") { $0[1] > 0 },
            Law(name: "bounded") { $0[0] + $0[1] < 10 },
        ]

        let verdict = engine.verify(controlPoints: cp, laws: laws)
        XCTAssertTrue(verdict.isCommit)
    }

    // MARK: - Exercise 11.3 from the paper

    func testExercise11_3_FirstViolationWitness() {
        // P0=(0,0), P1=(1,3), P2=(2,-1), P3=(3,0)
        // Law: y >= 0
        // Expected: violation at t* = 3/4
        let engine = NewtonEngine(budget: .highPrecision)

        let cp = ControlPoints(
            p0: StateVector(0.0, 0.0),
            p1: StateVector(1.0, 3.0),
            p2: StateVector(2.0, -1.0),
            p3: StateVector(3.0, 0.0)
        )

        let law = Law(
            name: "y non-negative",
            predicate: { $0[1] >= 0 },
            violationMeasure: { $0[1] }
        )

        let verdict = engine.verify(controlPoints: cp, laws: [law])
        XCTAssertTrue(verdict.isFinfr)

        if let witness = verdict.witness {
            // The violation should be near t* = 0.75
            // With subdivision, we'll find it approximately there
            XCTAssertEqual(witness.lawName, "y non-negative")
            // The witness time should be close to 0.75
            // (exact value depends on subdivision granularity)
            XCTAssertGreaterThan(witness.time, 0.5)
        }
    }

    // MARK: - Master Example (Section 10)

    func testMasterExample_NaiveProposal_Finfr() {
        // First attempt: straight line from (1,1) to (9,5)
        // Should be rejected because it passes through the rectangle [2,4]×[1,3]
        let engine = NewtonEngine()

        let cp = ControlPoints.linear(
            from: StateVector(1.0, 1.0),
            to: StateVector(9.0, 5.0)
        )

        let laws = [
            Law(name: "boundary") { state in
                state[0] >= 0 && state[0] <= 10 && state[1] >= 0 && state[1] <= 6
            },
            Law(name: "rectangle avoidance") { state in
                !(state[0] >= 2 && state[0] <= 4 && state[1] >= 1 && state[1] <= 3)
            },
            Law(name: "circle avoidance") { state in
                let dx = state[0] - 7, dy = state[1] - 4
                return dx * dx + dy * dy > 1
            },
        ]

        let verdict = engine.verify(controlPoints: cp, laws: laws)
        XCTAssertTrue(verdict.isFinfr, "Naive straight-line proposal should be rejected")
    }

    func testMasterExample_AdjustedProposal_Fin() {
        // Second attempt: curve arcing above the rectangle
        // P0=(1,1), P1=(2,4.5), P2=(6,5.5), P3=(9,5)
        let engine = NewtonEngine()

        let cp = ControlPoints(
            p0: StateVector(1.0, 1.0),
            p1: StateVector(2.0, 4.5),
            p2: StateVector(6.0, 5.5),
            p3: StateVector(9.0, 5.0)
        )

        let laws = [
            Law(name: "boundary") { state in
                state[0] >= 0 && state[0] <= 10 && state[1] >= 0 && state[1] <= 6
            },
            Law(name: "rectangle avoidance") { state in
                !(state[0] >= 2 && state[0] <= 4 && state[1] >= 1 && state[1] <= 3)
            },
            Law(name: "circle avoidance") { state in
                let dx = state[0] - 7, dy = state[1] - 4
                return dx * dx + dy * dy > 1
            },
        ]

        let verdict = engine.verify(controlPoints: cp, laws: laws)
        XCTAssertTrue(verdict.isCommit, "Adjusted arcing proposal should be accepted")
    }

    // MARK: - Exercise 11.2 — Convex Hull Inside Convex Region

    func testExercise11_2_ConvexHullVerification() {
        // P0=(0,0), P1=(1,2), P2=(3,1)
        // Ω = {(x,y) | x+y ≤ 5 ∧ x ≥ 0 ∧ y ≥ 0}
        // Since Ω is convex and all control points are in Ω,
        // the entire curve should be admissible.
        let engine = NewtonEngine()

        // Using a quadratic curve embedded as cubic (P2=P3 workaround: use linear from P0 to P2 with P1 as guide)
        // Actually, let's use three points as a cubic with repeated endpoint
        let cp = ControlPoints(
            p0: StateVector(0.0, 0.0),
            p1: StateVector(1.0, 2.0),
            p2: StateVector(3.0, 1.0),
            p3: StateVector(3.0, 1.0)  // degenerate: P2 = P3
        )

        let laws = [
            Law(name: "x+y ≤ 5") { $0[0] + $0[1] <= 5 },
            Law(name: "x ≥ 0") { $0[0] >= 0 },
            Law(name: "y ≥ 0") { $0[1] >= 0 },
        ]

        let verdict = engine.verify(controlPoints: cp, laws: laws)
        XCTAssertTrue(verdict.isCommit, "All control points in convex Ω → admissible")
    }
}
