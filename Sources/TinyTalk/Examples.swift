// Examples.swift — Concrete tinyTalk types demonstrating the DSL
// These examples show how the six reserved words map to Swift constructs.

import Foundation

// MARK: - Invoice Example
//
// The canonical tinyTalk example from the specification:
//
//   @Field var amount: Number = 0
//   @Field var status: String = "draft"
//   @Field var approved: Bool = false
//
// Rules enforce: positive amount, valid status path, approval before payment.
// Forges define: submit, approve, pay.

/// An invoice modeled as a tinyTalk Blueprint.
///
/// Demonstrates all six reserved words:
/// - `field` → @Field property wrapper
/// - `number` → Number type (Decimal-backed)
/// - `rule` → result builder block
/// - `when` → condition function
/// - `fin` → commit signal
/// - `finfr` → rejection signal
public final class Invoice: BlueprintObject {
    @Field public var amount: Number = 0
    @Field public var status: String = "draft"
    @Field public var approved: Bool = false

    public override init(engine: NewtonEngine = NewtonEngine(), ledger: Ledger = Ledger()) {
        super.init(engine: engine, ledger: ledger)
    }

    // MARK: - Field Registration

    public override func collectFields() -> [AnyFieldBox] {
        _amount.name = "amount"
        _amount.index = 0

        _status.name = "status"
        _status.index = 1
        _status.statePath = StatePath("draft", "submitted", "approved", "paid")

        _approved.name = "approved"
        _approved.index = 2

        return [
            AnyFieldBox(
                name: "amount",
                index: 0,
                getCurrentValue: { [weak self] in self?._amount.currentStateValue ?? 0 },
                getProposedValue: { [weak self] in self?._amount.proposedStateValue ?? 0 },
                beginForge: { [weak self] in self?._amount.beginForge() },
                commit: { [weak self] in self?._amount.commit() },
                rollback: { [weak self] in self?._amount.rollback() }
            ),
            AnyFieldBox(
                name: "status",
                index: 1,
                getCurrentValue: { [weak self] in
                    guard let self = self,
                          let path = self._status.statePath,
                          let idx = path.index(of: self._status.committedValue)
                    else { return 0 }
                    return Double(idx)
                },
                getProposedValue: { [weak self] in
                    guard let self = self,
                          let path = self._status.statePath,
                          let idx = path.index(of: self._status.wrappedValue)
                    else { return 0 }
                    return Double(idx)
                },
                beginForge: { [weak self] in self?._status.beginForge() },
                commit: { [weak self] in self?._status.commit() },
                rollback: { [weak self] in self?._status.rollback() }
            ),
            AnyFieldBox(
                name: "approved",
                index: 2,
                getCurrentValue: { [weak self] in self?._approved.currentStateValue ?? 0 },
                getProposedValue: { [weak self] in self?._approved.proposedStateValue ?? 0 },
                beginForge: { [weak self] in self?._approved.beginForge() },
                commit: { [weak self] in self?._approved.commit() },
                rollback: { [weak self] in self?._approved.rollback() }
            ),
        ]
    }

    // MARK: - Rules

    public override func collectRules() -> [Rule] {
        [
            rule("positive amount") {
                when(self.amount > 0, label: "amount > 0")
            },

            rule("valid status path") {
                when(
                    self.$status,
                    moves: "draft", to: "submitted", to: "approved", to: "paid"
                )
            },

            rule("approval required for payment") {
                when(self.$approved, before: self.$status, moves: "paid")
            },
        ]
    }

    // MARK: - Forges

    public override func collectForges() -> [ForgeDefinition] {
        [
            TinyTalk.forge("submit") {
                self.$status.moves(to: "submitted")
                fin
            },

            TinyTalk.forge("approve") {
                self.$approved.wrappedValue = true
                self.$status.moves(to: "approved")
                fin
            },

            TinyTalk.forge("pay") {
                if self.amount > Number(10000) && !self.approved {
                    finfr("Payment over 10000 requires approval")
                } else {
                    self.$status.moves(to: "paid")
                    fin
                }
            },

            TinyTalk.forge("set_amount") {
                // Amount is set before this forge is called via direct field access
                fin
            },
        ]
    }
}

// MARK: - Navigation Example (Master Worked Example from Section 10)

/// A 2D navigation agent demonstrating the master worked example
/// from Section 10 of Le Bézier du calcul V4.0.
///
/// State space: position (x, y) in [0,10] × [0,6]
/// Laws:
///   L1: Boundary — stay inside [0,10] × [0,6]
///   L2: Rectangular obstacle avoidance — avoid [2,4] × [1,3]
///   L3: Circular zone avoidance — avoid circle at (7,4) radius 1
public final class Navigator: BlueprintObject {
    @Field public var x: Number = 0
    @Field public var y: Number = 0

    public override init(engine: NewtonEngine = NewtonEngine(), ledger: Ledger = Ledger()) {
        super.init(engine: engine, ledger: ledger)
    }

    /// Initialize at a specific position.
    public convenience init(x: Number, y: Number) {
        self.init()
        // Set initial position directly
        self._x.wrappedValue = x
        self._y.wrappedValue = y
    }

    public override func collectFields() -> [AnyFieldBox] {
        _x.name = "x"
        _x.index = 0
        _y.name = "y"
        _y.index = 1

        return [
            AnyFieldBox(
                name: "x",
                index: 0,
                getCurrentValue: { [weak self] in self?._x.currentStateValue ?? 0 },
                getProposedValue: { [weak self] in self?._x.proposedStateValue ?? 0 },
                beginForge: { [weak self] in self?._x.beginForge() },
                commit: { [weak self] in self?._x.commit() },
                rollback: { [weak self] in self?._x.rollback() }
            ),
            AnyFieldBox(
                name: "y",
                index: 1,
                getCurrentValue: { [weak self] in self?._y.currentStateValue ?? 0 },
                getProposedValue: { [weak self] in self?._y.proposedStateValue ?? 0 },
                beginForge: { [weak self] in self?._y.beginForge() },
                commit: { [weak self] in self?._y.commit() },
                rollback: { [weak self] in self?._y.rollback() }
            ),
        ]
    }

    public override func collectRules() -> [Rule] {
        [
            // L1: Boundary — stay inside [0,10] × [0,6]
            rule("boundary") {
                when(
                    self.x >= 0 && self.x <= Number(10) && self.y >= 0 && self.y <= Number(6),
                    label: "0 ≤ x ≤ 10 ∧ 0 ≤ y ≤ 6"
                )
            },

            // L2: Rectangular obstacle avoidance — avoid [2,4] × [1,3]
            rule("rectangle avoidance") {
                when(
                    !(self.x >= Number(2) && self.x <= Number(4) && self.y >= Number(1) && self.y <= Number(3)),
                    label: "¬(2 ≤ x ≤ 4 ∧ 1 ≤ y ≤ 3)"
                )
            },

            // L3: Circular zone avoidance — avoid circle at (7,4) radius 1
            rule("circle avoidance") {
                when({
                    let dx = self.x - Number(7)
                    let dy = self.y - Number(4)
                    return (dx * dx + dy * dy) > Number(1)
                }(), label: "(x-7)² + (y-4)² > 1")
            },
        ]
    }

    public override func collectForges() -> [ForgeDefinition] {
        [
            TinyTalk.forge("move") {
                // Target position is set before calling forge
                fin
            },
        ]
    }

    /// Move to a target position using a direct Bézier trajectory.
    ///
    /// This constructs P₀ = current position, P₃ = target position,
    /// builds the trajectory, and verifies it against all laws.
    @discardableResult
    public func moveTo(x targetX: Number, y targetY: Number) -> Verdict {
        ensureRegistered()

        let p0 = currentStateVector()
        let p3 = StateVector([targetX.doubleValue, targetY.doubleValue])
        let controlPoints = ControlPoints.linear(from: p0, to: p3)

        let laws = makeLaws()
        let verdict = runtime.engine.verify(controlPoints: controlPoints, laws: laws)

        switch verdict {
        case .fin:
            _x.wrappedValue = targetX
            _y.wrappedValue = targetY
            runtime.ledger.append(
                controlPoints: controlPoints,
                lawNames: collectRules().map(\.name),
                verdict: .fin,
                forgeName: "moveTo(\(targetX), \(targetY))",
                blueprintType: "Navigator"
            )
            return .fin

        case .finfr(let witness):
            runtime.ledger.append(
                controlPoints: controlPoints,
                lawNames: collectRules().map(\.name),
                verdict: .finfr(witness),
                forgeName: "moveTo(\(targetX), \(targetY))",
                blueprintType: "Navigator"
            )
            return .finfr(witness)
        }
    }

    /// Move using custom control points (for curved trajectories).
    @discardableResult
    public func moveAlong(
        p1: (Number, Number),
        p2: (Number, Number),
        to target: (Number, Number)
    ) -> Verdict {
        ensureRegistered()

        let p0 = currentStateVector()
        let controlPoints = ControlPoints(
            p0: p0,
            p1: StateVector([p1.0.doubleValue, p1.1.doubleValue]),
            p2: StateVector([p2.0.doubleValue, p2.1.doubleValue]),
            p3: StateVector([target.0.doubleValue, target.1.doubleValue])
        )

        let laws = makeLaws()
        let verdict = runtime.engine.verify(controlPoints: controlPoints, laws: laws)

        switch verdict {
        case .fin:
            _x.wrappedValue = target.0
            _y.wrappedValue = target.1
            runtime.ledger.append(
                controlPoints: controlPoints,
                lawNames: collectRules().map(\.name),
                verdict: .fin,
                forgeName: "moveAlong",
                blueprintType: "Navigator"
            )
            return .fin

        case .finfr(let witness):
            runtime.ledger.append(
                controlPoints: controlPoints,
                lawNames: collectRules().map(\.name),
                verdict: .finfr(witness),
                forgeName: "moveAlong",
                blueprintType: "Navigator"
            )
            return .finfr(witness)
        }
    }

    /// Build the Law array for the Newton engine from our geometric constraints.
    /// These laws operate directly on the state vector (not through Field wrappers).
    private func makeLaws() -> [Law] {
        [
            // L1: Boundary
            Law(
                name: "boundary",
                predicate: { state in
                    let x = state[0], y = state[1]
                    return x >= 0 && x <= 10 && y >= 0 && y <= 6
                },
                violationMeasure: { state in
                    let x = state[0], y = state[1]
                    return Swift.min(x, 10 - x, y, 6 - y)
                }
            ),

            // L2: Rectangular obstacle avoidance
            Law(
                name: "rectangle avoidance",
                predicate: { state in
                    let x = state[0], y = state[1]
                    return !(x >= 2 && x <= 4 && y >= 1 && y <= 3)
                },
                violationMeasure: { state in
                    let x = state[0], y = state[1]
                    if x >= 2 && x <= 4 && y >= 1 && y <= 3 {
                        // Inside obstacle — negative margin
                        let dx = Swift.min(abs(x - 2), abs(x - 4))
                        let dy = Swift.min(abs(y - 1), abs(y - 3))
                        return -Swift.min(dx, dy)
                    }
                    // Outside obstacle — positive margin
                    if x >= 2 && x <= 4 {
                        return Swift.min(abs(y - 1), abs(y - 3))
                    }
                    if y >= 1 && y <= 3 {
                        return Swift.min(abs(x - 2), abs(x - 4))
                    }
                    let dx = x < 2 ? 2 - x : x - 4
                    let dy = y < 1 ? 1 - y : y - 3
                    return sqrt(dx * dx + dy * dy)
                }
            ),

            // L3: Circular zone avoidance
            Law(
                name: "circle avoidance",
                predicate: { state in
                    let x = state[0], y = state[1]
                    let dx = x - 7, dy = y - 4
                    return dx * dx + dy * dy > 1
                },
                violationMeasure: { state in
                    let x = state[0], y = state[1]
                    let dx = x - 7, dy = y - 4
                    return sqrt(dx * dx + dy * dy) - 1
                }
            ),
        ]
    }
}
