// Field.swift — @Field property wrapper
// Intercepts every write, tracks state for Bézier trajectory construction.
//
// The @Field property wrapper is one of tinyTalk's six reserved words.
// It wraps a value and provides:
//   1. Change tracking — knows the previous value for constructing P₀
//   2. Projection — proposes a new value without committing (P₃)
//   3. State vector encoding — converts typed values to Double for the engine
//   4. State path transitions — validates ordered enum-like transitions

import Foundation

// MARK: - FieldConvertible

/// Protocol for types that can be encoded into a state vector dimension.
/// Every type used with @Field must conform to this.
public protocol FieldConvertible {
    /// Encode this value as a Double for the Bézier engine.
    var stateValue: Double { get }

    /// Decode from a Double state value.
    static func fromStateValue(_ value: Double) -> Self
}

extension Number: FieldConvertible {
    public var stateValue: Double { doubleValue }

    public static func fromStateValue(_ value: Double) -> Number {
        Number(value)
    }
}

extension Bool: FieldConvertible {
    public var stateValue: Double { self ? 1.0 : 0.0 }

    public static func fromStateValue(_ value: Double) -> Bool {
        value >= 0.5
    }
}

extension Int: FieldConvertible {
    public var stateValue: Double { Double(self) }

    public static func fromStateValue(_ value: Double) -> Int {
        Int(value.rounded())
    }
}

extension Double: FieldConvertible {
    public var stateValue: Double { self }

    public static func fromStateValue(_ value: Double) -> Double {
        value
    }
}

// MARK: - String as FieldConvertible via State Paths

/// Strings are field-convertible when they represent states in a finite state machine.
/// The state index is the numeric encoding.
extension String: FieldConvertible {
    public var stateValue: Double {
        // Strings get their index from the StatePath they're registered with.
        // Default to hashing if no path is set.
        Double(self.hashValue & 0xFFFF)
    }

    public static func fromStateValue(_ value: Double) -> String {
        // Cannot reconstruct a string from a double without context.
        // This is handled by the Field wrapper which keeps the string value.
        "<state:\(Int(value))>"
    }
}

// MARK: - StatePath

/// Represents a valid sequence of state transitions for a string field.
///
/// Used with `when(status, moves: "draft", to: "submitted", to: "approved")` syntax.
/// The state path defines both the valid states and the valid transition ordering.
public struct StatePath: Sendable {
    /// The ordered list of states. Transitions are only valid in order.
    public let states: [String]

    /// Map from state name to its index in the path.
    public let stateIndices: [String: Int]

    public init(_ states: String...) {
        self.states = states
        var indices: [String: Int] = [:]
        for (i, s) in states.enumerated() {
            indices[s] = i
        }
        self.stateIndices = indices
    }

    public init(states: [String]) {
        self.states = states
        var indices: [String: Int] = [:]
        for (i, s) in states.enumerated() {
            indices[s] = i
        }
        self.stateIndices = indices
    }

    /// Check if a transition from `from` to `to` is valid (forward movement).
    public func isValidTransition(from: String, to: String) -> Bool {
        guard let fromIdx = stateIndices[from], let toIdx = stateIndices[to] else {
            return false
        }
        return toIdx > fromIdx
    }

    /// Check if a transition is exactly one step forward.
    public func isNextStep(from: String, to: String) -> Bool {
        guard let fromIdx = stateIndices[from], let toIdx = stateIndices[to] else {
            return false
        }
        return toIdx == fromIdx + 1
    }

    /// The numeric index for a state (used in state vector encoding).
    public func index(of state: String) -> Int? {
        stateIndices[state]
    }

    /// Whether a state is a member of this path.
    public func contains(_ state: String) -> Bool {
        stateIndices[state] != nil
    }
}

// MARK: - FieldMetadata

/// Metadata about a field, used by the Blueprint to construct state vectors.
public struct FieldMetadata: Sendable {
    public let name: String
    public let index: Int
    public let statePath: StatePath?
}

// MARK: - @Field Property Wrapper

/// The `@Field` property wrapper tracks state for Bézier trajectory construction.
///
/// Every mutation to a `@Field`-wrapped property goes through Newton before
/// committing. The wrapper tracks:
/// - The current committed value
/// - A proposed value (during forge execution)
/// - The field's index in the state vector
/// - An optional state path for string fields
///
/// Usage:
/// ```swift
/// @Field var amount: Number = 0
/// @Field var status: String = "draft"
/// @Field var approved: Bool = false
/// ```
@propertyWrapper
public final class Field<Value: FieldConvertible & Sendable>: @unchecked Sendable {
    /// The committed value.
    private var _value: Value

    /// The proposed value during a forge (nil when no forge is active).
    internal var proposed: Value?

    /// The field name (set during Blueprint registration).
    public internal(set) var name: String = ""

    /// The field's index in the state vector (set during Blueprint registration).
    public internal(set) var index: Int = -1

    /// State path for ordered string transitions (optional).
    public internal(set) var statePath: StatePath?

    /// Whether a forge is currently executing (mutations go to proposed).
    internal var isForging: Bool = false

    /// Reference back to the owning Blueprint's engine context.
    internal weak var engineContext: EngineContext?

    public init(wrappedValue: Value) {
        self._value = wrappedValue
    }

    public var wrappedValue: Value {
        get {
            // During a forge, return the proposed value if set
            if isForging, let p = proposed {
                return p
            }
            return _value
        }
        set {
            if isForging {
                proposed = newValue
            } else {
                _value = newValue
            }
        }
    }

    public var projectedValue: Field<Value> {
        self
    }

    /// The current committed value (ignoring any proposal).
    public var committedValue: Value {
        _value
    }

    /// The state value for the current committed state (P₀ component).
    public var currentStateValue: Double {
        _value.stateValue
    }

    /// The state value for the proposed state (P₃ component).
    public var proposedStateValue: Double {
        (proposed ?? _value).stateValue
    }

    /// Commit the proposed value as the new current value.
    internal func commit() {
        if let p = proposed {
            _value = p
        }
        proposed = nil
        isForging = false
    }

    /// Roll back the proposed value.
    internal func rollback() {
        proposed = nil
        isForging = false
    }

    /// Begin a forge — subsequent writes go to proposed.
    internal func beginForge() {
        isForging = true
        proposed = nil
    }
}

// MARK: - Field<String> extensions for state transitions

extension Field where Value == String {
    /// Propose a state transition. Used in forge blocks:
    /// ```swift
    /// status.moves(to: "submitted")
    /// ```
    public func moves(to newState: String) {
        if let path = statePath {
            // Validate transition order
            let current = isForging && proposed != nil ? proposed! : committedValue
            guard path.isValidTransition(from: current, to: newState) else {
                // Invalid transition — will be caught by rules
                proposed = newState
                return
            }
        }
        proposed = newState
    }
}

// MARK: - Engine Context

/// Weak reference holder for Blueprint-to-Engine communication.
public class EngineContext: @unchecked Sendable {
    public weak var blueprint: (any BlueprintInternal)?

    public init() {}
}
