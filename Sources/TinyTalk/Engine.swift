// Engine.swift — The Newton verification engine
// Implements verify_bezier from Le Bézier du calcul V4.0, Section 4.4.
// De Casteljau subdivision, convex hull checks, witness construction.

import Foundation

// MARK: - State Vector

/// A point in state space X, represented as a vector of Doubles.
/// Each dimension corresponds to a numeric field in a Blueprint.
public struct StateVector: Sendable, Equatable {
    public var components: [Double]

    public init(_ components: [Double]) {
        self.components = components
    }

    public init(_ components: Double...) {
        self.components = components
    }

    public var dimension: Int { components.count }

    public subscript(index: Int) -> Double {
        get { components[index] }
        set { components[index] = newValue }
    }

    /// Euclidean norm.
    public var norm: Double {
        sqrt(components.reduce(0.0) { $0 + $1 * $1 })
    }

    /// Distance to another state vector.
    public func distance(to other: StateVector) -> Double {
        (self - other).norm
    }

    // Vector arithmetic
    public static func + (lhs: StateVector, rhs: StateVector) -> StateVector {
        precondition(lhs.dimension == rhs.dimension)
        return StateVector(zip(lhs.components, rhs.components).map(+))
    }

    public static func - (lhs: StateVector, rhs: StateVector) -> StateVector {
        precondition(lhs.dimension == rhs.dimension)
        return StateVector(zip(lhs.components, rhs.components).map(-))
    }

    public static func * (scalar: Double, vec: StateVector) -> StateVector {
        StateVector(vec.components.map { scalar * $0 })
    }

    public static func * (vec: StateVector, scalar: Double) -> StateVector {
        scalar * vec
    }
}

// MARK: - Control Points (Cubic Bézier)

/// The four control points of a cubic Bézier trajectory.
///
/// P₀ = current state, P₃ = proposed target.
/// P₁ and P₂ are intermediate control points that shape the trajectory.
public struct ControlPoints: Sendable {
    public var p0: StateVector
    public var p1: StateVector
    public var p2: StateVector
    public var p3: StateVector

    public init(p0: StateVector, p1: StateVector, p2: StateVector, p3: StateVector) {
        precondition(p0.dimension == p1.dimension)
        precondition(p0.dimension == p2.dimension)
        precondition(p0.dimension == p3.dimension)
        self.p0 = p0
        self.p1 = p1
        self.p2 = p2
        self.p3 = p3
    }

    /// Construct a linear trajectory (all control points collinear).
    public static func linear(from start: StateVector, to end: StateVector) -> ControlPoints {
        let p1 = start + (1.0 / 3.0) * (end - start)
        let p2 = start + (2.0 / 3.0) * (end - start)
        return ControlPoints(p0: start, p1: p1, p2: p2, p3: end)
    }

    /// All four control points as an array.
    public var all: [StateVector] { [p0, p1, p2, p3] }

    /// Evaluate the cubic Bézier curve at parameter t ∈ [0,1].
    ///
    /// γ(t) = (1-t)³P₀ + 3(1-t)²tP₁ + 3(1-t)t²P₂ + t³P₃
    public func evaluate(at t: Double) -> StateVector {
        let u = 1.0 - t
        let u2 = u * u
        let u3 = u2 * u
        let t2 = t * t
        let t3 = t2 * t

        let b0 = u3
        let b1 = 3.0 * u2 * t
        let b2 = 3.0 * u * t2
        let b3 = t3

        let dim = p0.dimension
        var result = [Double](repeating: 0.0, count: dim)
        for d in 0..<dim {
            result[d] = b0 * p0[d] + b1 * p1[d] + b2 * p2[d] + b3 * p3[d]
        }
        return StateVector(result)
    }

    /// Derivative of the cubic Bézier at parameter t.
    ///
    /// γ'(t) = 3[(1-t)²(P₁-P₀) + 2(1-t)t(P₂-P₁) + t²(P₃-P₂)]
    public func derivative(at t: Double) -> StateVector {
        let u = 1.0 - t
        let d01 = p1 - p0
        let d12 = p2 - p1
        let d23 = p3 - p2

        return 3.0 * (u * u * d01 + 2.0 * u * t * d12 + t * t * d23)
    }
}

// MARK: - Law (Predicate on State Space)

/// A law L_i : X → {⊤, ⊥} that classifies states as lawful or unlawful.
///
/// In the paper: Definition 3.1. A law is a predicate that returns true (⊤)
/// when a state satisfies the constraint and false (⊥) when it violates.
public struct Law: Sendable {
    /// Human-readable name for this law.
    public let name: String

    /// The predicate. Returns true if the state is lawful under this law.
    public let predicate: @Sendable (StateVector) -> Bool

    /// Optional continuous violation measure ℓ_i : X → ℝ where ℓ_i(x) ≥ 0 iff L_i(x) = ⊤.
    /// Used for Lipschitz bounds (Section 5.2) and repair direction computation (Eq. 6).
    public let violationMeasure: (@Sendable (StateVector) -> Double)?

    public init(
        name: String,
        predicate: @escaping @Sendable (StateVector) -> Bool,
        violationMeasure: (@Sendable (StateVector) -> Double)? = nil
    ) {
        self.name = name
        self.predicate = predicate
        self.violationMeasure = violationMeasure
    }

    /// Check if a state is lawful under this law.
    public func check(_ state: StateVector) -> Bool {
        predicate(state)
    }
}

// MARK: - Witness

/// First-violation witness W = (i*, t*, γ(t*), Δ) from Definition 4.5.
///
/// - `lawIndex`: index i* of the violated law
/// - `time`: parameter t* where the first violation occurs
/// - `state`: the state γ(t*) at the violation point
/// - `repair`: suggested repair direction Δ in control-point space
/// - `reason`: human-readable description of why the violation occurred
public struct Witness: Sendable, CustomStringConvertible {
    public let lawIndex: Int
    public let lawName: String
    public let time: Double
    public let state: StateVector
    public let repair: StateVector?
    public let reason: String

    public init(
        lawIndex: Int,
        lawName: String,
        time: Double,
        state: StateVector,
        repair: StateVector?,
        reason: String
    ) {
        self.lawIndex = lawIndex
        self.lawName = lawName
        self.time = time
        self.state = state
        self.repair = repair
        self.reason = reason
    }

    public var description: String {
        var s = "Witness(law: \"\(lawName)\" [#\(lawIndex)], t=\(String(format: "%.4f", time)), state=\(state.components)"
        if let r = repair {
            s += ", repair=\(r.components)"
        }
        s += ", reason: \(reason))"
        return s
    }
}

// MARK: - Verdict

/// The result of verification: either fin (commit) or finfr (reject with witness).
public enum Verdict: Sendable {
    /// The entire trajectory is admissible. Commit to P₃.
    case fin

    /// The trajectory violates at least one law. No state mutation.
    case finfr(Witness)

    public var isCommit: Bool {
        if case .fin = self { return true }
        return false
    }

    public var isFinfr: Bool {
        if case .finfr = self { return true }
        return false
    }

    public var witness: Witness? {
        if case .finfr(let w) = self { return w }
        return nil
    }
}

// MARK: - Verification Budget

/// Controls the resource bounds for the verification algorithm.
public struct VerificationBudget: Sendable {
    /// Maximum recursion depth for de Casteljau subdivision.
    public var maxDepth: Int

    /// Tolerance: when the control polygon diameter is below this,
    /// we sample the midpoint and accept/reject.
    public var tolerance: Double

    public init(maxDepth: Int = 20, tolerance: Double = 1e-10) {
        self.maxDepth = maxDepth
        self.tolerance = tolerance
    }

    /// Default budget suitable for most applications.
    public static let standard = VerificationBudget(maxDepth: 20, tolerance: 1e-10)

    /// High-precision budget for critical systems.
    public static let highPrecision = VerificationBudget(maxDepth: 40, tolerance: 1e-15)
}

// MARK: - De Casteljau Subdivision

/// De Casteljau split of a cubic Bézier at parameter s.
/// Returns (left, right) sub-curves, each a ControlPoints.
///
/// From Section 4.3:
/// Left:  (Q₀, Q₁, Q₂, Q₃) where Q₃ = γ(s)
/// Right: (Q₃, R₂, R₁, R₀) where R₀ = P₃
public func deCasteljauSplit(
    _ cp: ControlPoints,
    at s: Double
) -> (left: ControlPoints, right: ControlPoints) {
    let u = 1.0 - s

    // Level 1
    let m01 = u * cp.p0 + s * cp.p1
    let m12 = u * cp.p1 + s * cp.p2
    let m23 = u * cp.p2 + s * cp.p3

    // Level 2
    let m012 = u * m01 + s * m12
    let m123 = u * m12 + s * m23

    // Level 3 — the point on the curve
    let mid = u * m012 + s * m123

    let left = ControlPoints(p0: cp.p0, p1: m01, p2: m012, p3: mid)
    let right = ControlPoints(p0: mid, p1: m123, p2: m23, p3: cp.p3)

    return (left, right)
}

// MARK: - Convex Hull Checks

/// Computes an axis-aligned bounding box for a set of points.
/// Returns (min, max) corners.
func boundingBox(of points: [StateVector]) -> (min: StateVector, max: StateVector) {
    guard let first = points.first else {
        return (StateVector([]), StateVector([]))
    }
    var lo = first.components
    var hi = first.components
    for p in points.dropFirst() {
        for d in 0..<p.dimension {
            lo[d] = Swift.min(lo[d], p[d])
            hi[d] = Swift.max(hi[d], p[d])
        }
    }
    return (StateVector(lo), StateVector(hi))
}

/// Maximum distance between any two control points (diameter of control polygon).
func controlPolygonDiameter(_ points: [StateVector]) -> Double {
    var maxDist = 0.0
    for i in 0..<points.count {
        for j in (i + 1)..<points.count {
            maxDist = Swift.max(maxDist, points[i].distance(to: points[j]))
        }
    }
    return maxDist
}

/// Check if all control points satisfy all laws.
/// This is the "hull inside Ω" quick-accept from Section 4.4.
///
/// When Ω is convex and all control points are in Ω, the entire curve
/// is in Ω by Theorem 4.1 (Convex Hull Containment).
///
/// For non-convex Ω, checking all control points is a heuristic quick-accept
/// that becomes exact as subdivision refines the control polygon to approximate
/// the curve (Theorem 4.3).
func allPointsSatisfyLaws(_ points: [StateVector], laws: [Law]) -> Bool {
    for point in points {
        for law in laws {
            if !law.check(point) {
                return false
            }
        }
    }
    return true
}

/// Check if any control point violates any law.
/// This is used for the "hull disjoint from Ω" quick-reject check.
/// Returns the first violated (lawIndex, pointIndex) or nil.
func findFirstViolation(_ points: [StateVector], laws: [Law]) -> (lawIndex: Int, pointIndex: Int)? {
    for (pi, point) in points.enumerated() {
        for (li, law) in laws.enumerated() {
            if !law.check(point) {
                return (li, pi)
            }
        }
    }
    return nil
}

// MARK: - Bernstein Basis

/// Bernstein basis polynomial b_{i,n}(t) = C(n,i) * t^i * (1-t)^(n-i)
func bernsteinBasis(i: Int, n: Int, t: Double) -> Double {
    let coeff = binomialCoefficient(n, i)
    return Double(coeff) * pow(t, Double(i)) * pow(1.0 - t, Double(n - i))
}

/// Binomial coefficient C(n, k)
func binomialCoefficient(_ n: Int, _ k: Int) -> Int {
    if k < 0 || k > n { return 0 }
    if k == 0 || k == n { return 1 }
    var result = 1
    let k = min(k, n - k)
    for i in 0..<k {
        result = result * (n - i) / (i + 1)
    }
    return result
}

// MARK: - Repair Direction

/// Compute the repair direction Δ from Equation 6 in the paper.
///
/// Δₖ = -η · ∇_{Pₖ} max(0, -ℓ_{i*}(γ(t*)))
///
/// where k is the control point with the largest Bernstein weight at t*.
func computeRepairDirection(
    controlPoints: ControlPoints,
    law: Law,
    lawIndex: Int,
    violationTime t: Double,
    violationState: StateVector,
    stepSize eta: Double = 0.1
) -> StateVector? {
    guard let measure = law.violationMeasure else { return nil }

    // Find which control point has the largest Bernstein weight at t*
    let weights = (0...3).map { bernsteinBasis(i: $0, n: 3, t: t) }
    let maxWeightIndex = weights.enumerated().max(by: { $0.element < $1.element })!.offset

    // Numerical gradient of the violation measure w.r.t. the responsible control point
    let eps = 1e-6
    let cp = controlPoints.all[maxWeightIndex]
    var gradient = [Double](repeating: 0.0, count: cp.dimension)

    for d in 0..<cp.dimension {
        var cpPlus = cp
        cpPlus[d] += eps

        // Reconstruct control points with perturbed point
        var allCps = controlPoints.all
        allCps[maxWeightIndex] = cpPlus
        let perturbedCP = ControlPoints(p0: allCps[0], p1: allCps[1], p2: allCps[2], p3: allCps[3])
        let perturbedState = perturbedCP.evaluate(at: t)

        let violation = max(0, -measure(perturbedState))
        let violationOriginal = max(0, -measure(violationState))
        gradient[d] = (violation - violationOriginal) / eps
    }

    // Δ = -η · gradient
    let repair = StateVector(gradient.map { -eta * $0 })
    return repair
}

// MARK: - The Newton Verification Engine

/// The Newton engine implements `verify_bezier` from Section 4.4.
///
/// This is the core of Le Bézier du calcul: given a cubic Bézier trajectory
/// (P₀, P₁, P₂, P₃) and a set of laws, determine whether the entire trajectory
/// γ(t) for t ∈ [0,1] remains within the lawful region Ω.
///
/// Returns `fin` if the trajectory is admissible, or `finfr` with a witness
/// identifying the first violation.
public struct NewtonEngine: Sendable {
    public let budget: VerificationBudget

    public init(budget: VerificationBudget = .standard) {
        self.budget = budget
    }

    /// Verify a Bézier trajectory against a set of laws.
    ///
    /// Direct translation of Listing 1 (Section 4.4):
    /// ```
    /// def verify_bezier(P0, P1, P2, P3, laws, budget):
    ///     stack = [(P0, P1, P2, P3, 0.0, 1.0, 0)]
    ///     while stack:
    ///         Q0, Q1, Q2, Q3, a, b, depth = stack.pop()
    ///         if depth > budget.max_depth:
    ///             return ("finfr", ("depth_exceeded", a))
    ///         if hull_disjoint(conv([Q0, Q1, Q2, Q3]), Omega, laws):
    ///             return ("finfr", ("hull_outside", a))
    ///         if hull_inside(conv([Q0, Q1, Q2, Q3]), Omega, laws):
    ///             continue
    ///         L, R = de_casteljau_split(Q0, Q1, Q2, Q3, 0.5)
    ///         mid = (a + b) / 2.0
    ///         stack.append((*R, mid, b, depth + 1))
    ///         stack.append((*L, a, mid, depth + 1))
    ///     return ("fin", None)
    /// ```
    public func verify(
        controlPoints cp: ControlPoints,
        laws: [Law]
    ) -> Verdict {
        // Stack entries: (controlPoints, paramStart, paramEnd, depth)
        var stack: [(ControlPoints, Double, Double, Int)] = [
            (cp, 0.0, 1.0, 0)
        ]

        while let (segment, a, b, depth) = stack.popLast() {
            let points = segment.all

            // Depth exceeded — return finfr conservatively
            if depth > budget.maxDepth {
                let midT = (a + b) / 2.0
                let state = segment.evaluate(at: 0.5)

                // Find which law is violated (or report depth exceeded)
                for (li, law) in laws.enumerated() {
                    if !law.check(state) {
                        let witness = Witness(
                            lawIndex: li,
                            lawName: law.name,
                            time: midT,
                            state: state,
                            repair: nil,
                            reason: "Subdivision depth exceeded at t≈\(String(format: "%.6f", midT)); law \"\(law.name)\" could not be verified"
                        )
                        return .finfr(witness)
                    }
                }

                // Depth exceeded but no violation found at midpoint — conservative reject
                let witness = Witness(
                    lawIndex: -1,
                    lawName: "(depth exceeded)",
                    time: midT,
                    state: state,
                    repair: nil,
                    reason: "Subdivision depth exceeded at t≈\(String(format: "%.6f", midT)); could not certify admissibility"
                )
                return .finfr(witness)
            }

            // Quick reject: check if any control point violates a law
            // (In the paper: hull_disjoint check)
            if let violation = findFirstViolation(points, laws: laws) {
                // A control point is outside Ω. This doesn't necessarily mean the
                // curve passes through this point, but for small segments it's a
                // strong signal. We need to verify more carefully.
                //
                // For the quick-reject to be sound, we check the actual curve point
                // at the corresponding parameter.
                let tLocal = Double(violation.pointIndex) / 3.0
                let tGlobal = a + tLocal * (b - a)
                let state = cp.evaluate(at: tGlobal)

                if !laws[violation.lawIndex].check(state) {
                    let repair = computeRepairDirection(
                        controlPoints: cp,
                        law: laws[violation.lawIndex],
                        lawIndex: violation.lawIndex,
                        violationTime: tGlobal,
                        violationState: state
                    )
                    let witness = Witness(
                        lawIndex: violation.lawIndex,
                        lawName: laws[violation.lawIndex].name,
                        time: tGlobal,
                        state: state,
                        repair: repair,
                        reason: "Law \"\(laws[violation.lawIndex].name)\" violated at t≈\(String(format: "%.6f", tGlobal))"
                    )
                    return .finfr(witness)
                }
            }

            // Quick accept: all control points satisfy all laws
            // By Theorem 4.3, as subdivision depth increases, the control polygon
            // converges to the curve. When the polygon is small enough and all
            // vertices are lawful, we can accept.
            if allPointsSatisfyLaws(points, laws: laws) {
                // Additional check: if the segment is small enough, accept
                let diameter = controlPolygonDiameter(points)
                if diameter < budget.tolerance || depth > 0 {
                    // For subdivided segments where all control points pass,
                    // this is the quick-accept
                    if allPointsSatisfyLaws(points, laws: laws) {
                        continue
                    }
                }
                // Even if diameter is large, if all CPs are in Ω, accept.
                // This is exact when Ω is convex (Theorem 4.1).
                continue
            }

            // Subdivide at midpoint using de Casteljau (Section 4.3)
            let (left, right) = deCasteljauSplit(segment, at: 0.5)
            let mid = (a + b) / 2.0

            // Push right first so left is processed first (stack is LIFO)
            // This ensures we find the earliest violation (smallest t*)
            stack.append((right, mid, b, depth + 1))
            stack.append((left, a, mid, depth + 1))
        }

        // All segments verified — the entire trajectory is admissible
        return .fin
    }

    /// Verify with a simple linear trajectory (straight line from start to end).
    public func verifyLinear(
        from start: StateVector,
        to end: StateVector,
        laws: [Law]
    ) -> Verdict {
        let cp = ControlPoints.linear(from: start, to: end)
        return verify(controlPoints: cp, laws: laws)
    }
}
