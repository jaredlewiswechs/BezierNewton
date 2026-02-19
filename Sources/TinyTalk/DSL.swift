// DSL.swift — Result builders, when/rule/forge constructs, fin/finfr
// The syntactic surface of tinyTalk as a Swift DSL.

import Foundation

// MARK: - Condition

/// A condition that can be evaluated against the current state.
/// Used inside `when(...)` blocks in rules and forges.
public struct Condition: Sendable {
    public let label: String
    public let evaluate: @Sendable () -> Bool

    public init(label: String, evaluate: @escaping @Sendable () -> Bool) {
        self.label = label
        self.evaluate = evaluate
    }

    public func check() -> Bool {
        evaluate()
    }
}

// MARK: - Rule

/// A named constraint rule containing one or more conditions.
///
/// Rules define the lawful region Ω. Every rule must hold for a trajectory
/// to be admissible (fin). If any rule fails, the proposal is rejected (finfr).
public struct Rule: Sendable {
    public let name: String
    public let conditions: [Condition]

    public init(name: String, conditions: [Condition]) {
        self.name = name
        self.conditions = conditions
    }

    /// Check if all conditions in this rule are satisfied.
    public func isSatisfied() -> Bool {
        conditions.allSatisfy { $0.check() }
    }

    /// Return the first failing condition, or nil if all pass.
    public func firstViolation() -> Condition? {
        conditions.first { !$0.check() }
    }
}

// MARK: - RuleBuilder

/// Result builder for constructing rules from `when(...)` expressions.
///
/// Usage:
/// ```swift
/// rule("positive amount") {
///     when(amount > 0)
/// }
/// ```
@resultBuilder
public struct RuleBuilder {
    public static func buildBlock(_ conditions: Condition...) -> [Condition] {
        conditions
    }

    public static func buildBlock(_ conditions: [Condition]) -> [Condition] {
        conditions
    }

    public static func buildOptional(_ conditions: [Condition]?) -> [Condition] {
        conditions ?? []
    }

    public static func buildEither(first conditions: [Condition]) -> [Condition] {
        conditions
    }

    public static func buildEither(second conditions: [Condition]) -> [Condition] {
        conditions
    }

    public static func buildArray(_ components: [[Condition]]) -> [Condition] {
        components.flatMap { $0 }
    }
}

// MARK: - RulesBuilder

/// Result builder for collecting multiple rules.
///
/// Usage:
/// ```swift
/// var rules: some Rules {
///     rule("positive amount") {
///         when(amount > 0)
///     }
///     rule("valid status") {
///         when(status, moves: "draft", to: "submitted", to: "approved")
///     }
/// }
/// ```
@resultBuilder
public struct RulesBuilder {
    public static func buildBlock(_ rules: Rule...) -> [Rule] {
        rules
    }

    public static func buildBlock(_ rules: [Rule]) -> [Rule] {
        rules
    }

    public static func buildOptional(_ rules: [Rule]?) -> [Rule] {
        rules ?? []
    }

    public static func buildEither(first rules: [Rule]) -> [Rule] {
        rules
    }

    public static func buildEither(second rules: [Rule]) -> [Rule] {
        rules
    }

    public static func buildArray(_ components: [[Rule]]) -> [Rule] {
        components.flatMap { $0 }
    }
}

// MARK: - Rules protocol

/// Opaque type for the rules property of a Blueprint.
public protocol Rules {
    var ruleList: [Rule] { get }
}

/// Concrete type returned by the RulesBuilder.
public struct RuleCollection: Rules {
    public let ruleList: [Rule]

    public init(_ rules: [Rule]) {
        self.ruleList = rules
    }
}

// MARK: - ForgeAction

/// An action performed during a forge execution.
public enum ForgeAction: Sendable {
    /// The forge completed successfully. Commit the proposed state.
    case commit

    /// The forge was rejected. Return finfr with a reason.
    case reject(String)

    /// The forge produced a conditional rejection.
    case conditionalReject(condition: String, reason: String)
}

// MARK: - ForgeResult

/// The result of executing a forge block.
public struct ForgeResult: Sendable {
    public let actions: [ForgeAction]

    public init(actions: [ForgeAction]) {
        self.actions = actions
    }

    /// Whether the forge should commit (no rejections in the action list).
    public var shouldCommit: Bool {
        !actions.contains(where: {
            switch $0 {
            case .reject, .conditionalReject: return true
            case .commit: return false
            }
        })
    }

    /// The first rejection reason, if any.
    public var rejectionReason: String? {
        for action in actions {
            switch action {
            case .reject(let reason): return reason
            case .conditionalReject(_, let reason): return reason
            case .commit: continue
            }
        }
        return nil
    }
}

// MARK: - ForgeBuilder

/// Result builder for constructing forge blocks.
///
/// Usage:
/// ```swift
/// forge("submit") {
///     status.moves(to: "submitted")
///     fin
/// }
/// ```
@resultBuilder
public struct ForgeBuilder {
    /// Absorbs side-effect expressions (e.g. `field.moves(to:)`, assignments)
    /// that return `Void`. They run for their effects; no action is emitted.
    public static func buildExpression(_ expression: Void) -> [ForgeAction] {
        []
    }

    /// Lifts a single `ForgeAction` (e.g. `fin`, `finfr`) into the builder.
    public static func buildExpression(_ expression: ForgeAction) -> [ForgeAction] {
        [expression]
    }

    public static func buildBlock(_ components: [ForgeAction]...) -> [ForgeAction] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ actions: [ForgeAction]?) -> [ForgeAction] {
        actions ?? []
    }

    public static func buildEither(first actions: [ForgeAction]) -> [ForgeAction] {
        actions
    }

    public static func buildEither(second actions: [ForgeAction]) -> [ForgeAction] {
        actions
    }

    public static func buildArray(_ components: [[ForgeAction]]) -> [ForgeAction] {
        components.flatMap { $0 }
    }
}

// MARK: - ForgesBuilder

/// Result builder for collecting multiple forge definitions.
@resultBuilder
public struct ForgesBuilder {
    public static func buildBlock(_ forges: ForgeDefinition...) -> [ForgeDefinition] {
        forges
    }

    public static func buildBlock(_ forges: [ForgeDefinition]) -> [ForgeDefinition] {
        forges
    }

    public static func buildOptional(_ forges: [ForgeDefinition]?) -> [ForgeDefinition] {
        forges ?? []
    }

    public static func buildEither(first forges: [ForgeDefinition]) -> [ForgeDefinition] {
        forges
    }

    public static func buildEither(second forges: [ForgeDefinition]) -> [ForgeDefinition] {
        forges
    }

    public static func buildArray(_ components: [[ForgeDefinition]]) -> [ForgeDefinition] {
        components.flatMap { $0 }
    }
}

/// Opaque type for the forges property of a Blueprint.
public protocol Forges {
    var forgeList: [ForgeDefinition] { get }
}

/// Concrete type returned by the ForgesBuilder.
public struct ForgeCollection: Forges {
    public let forgeList: [ForgeDefinition]

    public init(_ forges: [ForgeDefinition]) {
        self.forgeList = forges
    }
}

// MARK: - ForgeDefinition

/// A named forge with its body closure.
public struct ForgeDefinition {
    public let name: String
    public let body: () -> [ForgeAction]

    public init(name: String, body: @escaping () -> [ForgeAction]) {
        self.name = name
        self.body = body
    }
}

// MARK: - DSL Functions

/// `fin` — The commit signal. Used at the end of a forge block to indicate success.
///
/// In the paper: "If ∀t ∈ [0,1], γ(t) ∈ Ω, the proposal commits: the system
/// transitions to P₃. This is fin."
public let fin: ForgeAction = .commit

/// `finfr` — The rejection signal. Used in a forge block to abort the transition.
///
/// In the paper: "If ∃t such that γ(t) ∉ Ω, the proposal is rejected without
/// state mutation. This is finfr."
public let finfr: ForgeAction = .reject("Forge explicitly rejected (finfr)")

/// Create a rejection with a specific reason.
public func finfr(_ reason: String) -> ForgeAction {
    .reject(reason)
}

/// `when` — Create a condition from a boolean expression.
///
/// Usage in rules:
/// ```swift
/// rule("positive amount") {
///     when(amount > 0)
/// }
/// ```
///
/// Usage in forges:
/// ```swift
/// forge("pay") {
///     when(amount > 10000, and: !approved) {
///         finfr
///     }
///     fin
/// }
/// ```
public func when(_ condition: @autoclosure @escaping @Sendable () -> Bool, label: String = "") -> Condition {
    Condition(label: label, evaluate: condition)
}

/// `when` with two conditions joined by `and:`.
public func when(
    _ condition1: @autoclosure @escaping @Sendable () -> Bool,
    and condition2: @autoclosure @escaping @Sendable () -> Bool,
    label: String = ""
) -> Condition {
    Condition(label: label) {
        condition1() && condition2()
    }
}

/// `when` for state path transitions.
///
/// Usage:
/// ```swift
/// rule("valid status path") {
///     when(status, moves: "draft", to: "submitted", to: "approved", to: "paid")
/// }
/// ```
///
/// This creates a condition that checks the string field follows the given
/// ordered state path. The current value must be one of the listed states,
/// and any proposed change must move forward in the ordering.
public func when(_ field: Field<String>, moves first: String, to second: String) -> Condition {
    let path = StatePath(first, second)
    return Condition(label: "state path: \(first) → \(second)") {
        let current = field.wrappedValue
        return path.contains(current)
    }
}

/// `when` for state path with three states.
public func when(_ field: Field<String>, moves first: String, to second: String, to third: String) -> Condition {
    let path = StatePath(first, second, third)
    field.statePath = path
    return Condition(label: "state path: \(first) → \(second) → \(third)") {
        let current = field.wrappedValue
        return path.contains(current)
    }
}

/// `when` for state path with four states.
public func when(_ field: Field<String>, moves first: String, to second: String, to third: String, to fourth: String) -> Condition {
    let path = StatePath(first, second, third, fourth)
    field.statePath = path
    return Condition(label: "state path: \(first) → \(second) → \(third) → \(fourth)") {
        let current = field.wrappedValue
        return path.contains(current)
    }
}

/// `when` for state path with five states.
public func when(_ field: Field<String>, moves first: String, to s2: String, to s3: String, to s4: String, to s5: String) -> Condition {
    let path = StatePath(first, s2, s3, s4, s5)
    field.statePath = path
    return Condition(label: "state path: \(first) → \(s2) → \(s3) → \(s4) → \(s5)") {
        let current = field.wrappedValue
        return path.contains(current)
    }
}

/// `when` for a prerequisite condition before a state move.
///
/// Usage:
/// ```swift
/// rule("approval required for payment") {
///     when(approved, before: status, moves: "paid")
/// }
/// ```
///
/// This means: the `approved` field must be true before `status` can move to "paid".
public func when(_ field: Field<Bool>, before statusField: Field<String>, moves targetState: String) -> Condition {
    Condition(label: "require \(field.name) before \(statusField.name) moves to \(targetState)") {
        let statusValue = statusField.wrappedValue
        if statusValue == targetState {
            // If we're already at or proposing to move to the target state,
            // the prerequisite must be satisfied
            return field.wrappedValue
        }
        return true
    }
}

/// `rule` — Construct a named rule using a result builder.
///
/// Usage:
/// ```swift
/// rule("positive amount") {
///     when(amount > 0)
/// }
/// ```
public func rule(_ name: String, @RuleBuilder _ conditions: () -> [Condition]) -> Rule {
    Rule(name: name, conditions: conditions())
}

/// `forge` — Define a named forge (state transition) using a result builder.
///
/// Usage:
/// ```swift
/// forge("submit") {
///     status.moves(to: "submitted")
///     fin
/// }
/// ```
public func forge(_ name: String, @ForgeBuilder _ body: @escaping () -> [ForgeAction]) -> ForgeDefinition {
    ForgeDefinition(name: name, body: body)
}

// MARK: - Conditional forge actions

/// `when` in a forge context — produces a ForgeAction based on a condition.
///
/// Usage:
/// ```swift
/// forge("pay") {
///     when(amount > 10000, and: !approved) {
///         finfr
///     }
///     status.moves(to: "paid")
///     fin
/// }
/// ```
public func when(
    _ condition: @autoclosure @escaping () -> Bool,
    and condition2: @autoclosure @escaping () -> Bool,
    @ForgeBuilder then body: () -> [ForgeAction]
) -> ForgeAction {
    if condition() && condition2() {
        let actions = body()
        if let rejection = actions.first(where: {
            switch $0 {
            case .reject, .conditionalReject: return true
            case .commit: return false
            }
        }) {
            return rejection
        }
        return .commit
    }
    return .commit
}
