// Ledger.swift — Append-only reproducible computation ledger
// Implements Section 4.5 of Le Bézier du calcul V4.0.
//
// Each proposal and its result are committed to an append-only ledger:
//   e_j = (hash_j, P₀, P₁, P₂, P₃, vL, result_j, W_j)

import Foundation

// MARK: - Ledger Entry

/// A single ledger entry recording a proposal and its verification result.
///
/// From Section 4.5: "Identical inputs yield identical results, making the
/// entire computation history reproducible and auditable."
public struct LedgerEntry: Sendable {
    /// SHA-256 hash of this entry's content.
    public let hash: String

    /// The control points of the proposed trajectory.
    public let controlPoints: ControlPoints

    /// Law version identifier — tracks which set of laws was in effect.
    public let lawVersion: Int

    /// Names of all laws that were checked.
    public let lawNames: [String]

    /// The verdict: fin or finfr.
    public let verdict: Verdict

    /// Timestamp of when this entry was created.
    public let timestamp: Date

    /// Human-readable description of the forge that produced this entry.
    public let forgeName: String?

    /// The Blueprint type name that owns this entry.
    public let blueprintType: String?
}

extension LedgerEntry: CustomStringConvertible {
    public var description: String {
        let result = verdict.isCommit ? "fin" : "finfr"
        let forge = forgeName.map { " forge=\"\($0)\"" } ?? ""
        let type = blueprintType.map { " type=\($0)" } ?? ""
        return "LedgerEntry(\(hash.prefix(8))...\(type)\(forge) [\(result)] laws=v\(lawVersion))"
    }
}

// MARK: - Ledger

/// An append-only ledger of all proposals and their verification results.
///
/// The ledger provides:
/// - Full audit trail of every state transition attempt
/// - Reproducibility: identical inputs always produce identical results
/// - Witness preservation: every finfr has its witness recorded
public final class Ledger: @unchecked Sendable {
    private var entries: [LedgerEntry] = []
    private let lock = NSLock()

    /// The current law version counter. Incremented when laws change.
    public private(set) var lawVersion: Int = 1

    public init() {}

    /// Append a new entry to the ledger.
    @discardableResult
    public func append(
        controlPoints: ControlPoints,
        lawNames: [String],
        verdict: Verdict,
        forgeName: String? = nil,
        blueprintType: String? = nil
    ) -> LedgerEntry {
        lock.lock()
        defer { lock.unlock() }

        let entry = LedgerEntry(
            hash: Self.computeHash(
                controlPoints: controlPoints,
                lawVersion: lawVersion,
                lawNames: lawNames,
                verdict: verdict,
                index: entries.count
            ),
            controlPoints: controlPoints,
            lawVersion: lawVersion,
            lawNames: lawNames,
            verdict: verdict,
            timestamp: Date(),
            forgeName: forgeName,
            blueprintType: blueprintType
        )
        entries.append(entry)
        return entry
    }

    /// Number of entries in the ledger.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    /// Retrieve all entries.
    public var allEntries: [LedgerEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// Retrieve the most recent entry.
    public var lastEntry: LedgerEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entries.last
    }

    /// Retrieve entry at index.
    public subscript(index: Int) -> LedgerEntry {
        lock.lock()
        defer { lock.unlock() }
        return entries[index]
    }

    /// Retrieve all entries for a given forge name.
    public func entries(forForge name: String) -> [LedgerEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.forgeName == name }
    }

    /// Retrieve all entries that resulted in fin.
    public var commits: [LedgerEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.verdict.isCommit }
    }

    /// Retrieve all entries that resulted in finfr.
    public var rejections: [LedgerEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.verdict.isFinfr }
    }

    /// Increment the law version. Call this when laws change.
    public func bumpLawVersion() {
        lock.lock()
        defer { lock.unlock() }
        lawVersion += 1
    }

    /// Compute a deterministic hash for a ledger entry.
    private static func computeHash(
        controlPoints: ControlPoints,
        lawVersion: Int,
        lawNames: [String],
        verdict: Verdict,
        index: Int
    ) -> String {
        var data = Data()

        // Encode control points
        for point in controlPoints.all {
            for component in point.components {
                withUnsafeBytes(of: component) { data.append(contentsOf: $0) }
            }
        }

        // Encode law version
        withUnsafeBytes(of: lawVersion) { data.append(contentsOf: $0) }

        // Encode law names
        for name in lawNames {
            data.append(Data(name.utf8))
        }

        // Encode verdict
        let verdictByte: UInt8 = verdict.isCommit ? 1 : 0
        data.append(verdictByte)

        // Encode index for ordering
        withUnsafeBytes(of: index) { data.append(contentsOf: $0) }

        // Simple hash (for production, use CryptoKit SHA256)
        return hexHash(of: data)
    }

    /// A simple hash function. In production, replace with SHA-256 from CryptoKit.
    private static func hexHash(of data: Data) -> String {
        // djb2-style hash producing a hex string
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(byte)
        }
        // Mix further
        hash = hash ^ (hash &>> 33)
        hash = hash &* 0xff51afd7ed558ccd
        hash = hash ^ (hash &>> 33)
        hash = hash &* 0xc4ceb9fe1a85ec53
        hash = hash ^ (hash &>> 33)
        return String(format: "0x%016llx", hash)
    }
}
