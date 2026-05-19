import Foundation

/// Per-key bookkeeping for keyed search. Mirrors
/// `../fuse-js/src/tools/KeyStore.ts` minus the sum-to-1 weight
/// normalization. v1 keeps raw per-key weights; normalization only applies
/// to the deferred `_searchLogical` path.
///
/// Storage is parallel arrays indexed by **slot** (the position of the
/// `FuseKey` in user-supplied `options.keys`), plus an id → slot map for
/// lookups by joined dotted-path id.
final class KeyStore<Element> {
    let keys: [FuseKey<Element>]
    let keyPaths: [[String]]
    let keyIds: [String]
    let keyIdToSlot: [String: Int]

    init(_ keys: [FuseKey<Element>]) {
        self.keys = keys
        self.keyPaths = keys.map { KeyStore.keyPath(for: $0.source) }
        self.keyIds = keys.map { KeyStore.keyId(for: $0.source) }

        var map: [String: Int] = [:]
        for (slot, id) in keyIds.enumerated() {
            map[id] = slot
        }
        self.keyIdToSlot = map
    }

    func slot(forId id: String) -> Int? {
        keyIdToSlot[id]
    }

    /// Encode keys for the serialized index (drops accessors / closures).
    func serialized() -> [SerializedKey] {
        zip(keys, zip(keyPaths, keyIds)).map { key, pathAndId in
            let (path, id) = pathAndId
            return SerializedKey(path: path, id: id, weight: key.weight, src: key.source)
        }
    }

    // ── createKeyPath / createKeyId per upstream KeyStore.ts:77-83 ────

    static func keyPath(for source: KeySource) -> [String] {
        switch source {
        case .string(let s):
            return s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        case .array(let a):
            return a
        }
    }

    static func keyId(for source: KeySource) -> String {
        switch source {
        case .string(let s): return s
        case .array(let a): return a.joined(separator: ".")
        }
    }
}
