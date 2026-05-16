import Foundation

/// Default path walker used when a `FuseKey` is path-form and no top-level
/// `FuseOptions.getFn` is supplied. Mirrors `../fuse-js/src/helpers/get.ts`
/// against a JSON-encoded snapshot of the document.
///
/// `Element` must conform to `Encodable` for the default walker — checked
/// at runtime via `Element.self as? any Encodable.Type`. Non-`Encodable`
/// elements get a `FuseError.pathRequiresEncodableOrGetFn` at index-build
/// time. Per Edge Cases #1, the path follows **encoded JSON names** (i.e.
/// `CodingKeys` remapping is honored), not Swift property names.
///
/// JSON-tree representation uses `JSONValue` to preserve type discrimination
/// across the encode/decode round-trip (especially Bool, which `NSNumber`
/// loses without explicit handling).
enum ValueAccessor {
    /// Type-erased Encodable for routing `any Encodable` through
    /// `JSONEncoder.encode<T: Encodable>(_:)`.
    private struct AnyEncodable: Encodable {
        let value: any Encodable
        func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
    }

    /// Returns true iff `Element.self` conforms to `Encodable`. Used by
    /// `FuseIndex` to pre-flight `.path` keys.
    static func isEncodable<Element>(_ type: Element.Type) -> Bool {
        type as? any Encodable.Type != nil
    }

    /// Walk `path` against an `Encodable` element and return an
    /// `AccessorResult` mirroring `get.ts`. Throws `pathEncodingFailed` if
    /// `JSONEncoder.encode` fails; throws `pathRequiresEncodableOrGetFn` if
    /// `element` is not `Encodable` (defensive — callers pre-validate).
    static func defaultGet<Element>(_ element: Element, path: [String]) throws -> AccessorResult {
        guard let encodable = element as? any Encodable else {
            throw FuseError.pathRequiresEncodableOrGetFn(
                keyName: path.joined(separator: ".")
            )
        }
        let tree: JSONValue
        do {
            let data = try JSONEncoder().encode(AnyEncodable(value: encodable))
            tree = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw FuseError.pathEncodingFailed(
                keyName: path.joined(separator: "."),
                underlyingError: error
            )
        }

        var list: [(value: String, arrayIndex: Int?)] = []
        var arr = false
        walk(tree, path: path, index: 0, arrayIndex: nil, list: &list, arr: &arr)

        if arr {
            return .multiple(list.map {
                SubRecordValue(value: $0.value, index: $0.arrayIndex ?? 0)
            })
        }
        guard let first = list.first else { return .none }
        return .single(first.value)
    }

    private static func walk(
        _ node: JSONValue,
        path: [String],
        index: Int,
        arrayIndex: Int?,
        list: inout [(value: String, arrayIndex: Int?)],
        arr: inout Bool
    ) {
        if case .null = node { return }

        // Terminal: no path left, scalar pushes; non-scalar intermediate
        // objects are dropped (matches the upstream `_createObjectRecord`
        // filter that ignores non-{v,i} array items).
        if index >= path.count {
            if let s = scalarString(node) {
                list.append((value: s, arrayIndex: arrayIndex))
            }
            return
        }

        let key = path[index]
        guard case .object(let obj) = node, let value = obj[key] else { return }
        if case .null = value { return }

        if index == path.count - 1, let s = scalarString(value) {
            list.append((value: s, arrayIndex: arrayIndex))
            return
        }

        if case .array(let items) = value {
            arr = true
            for (i, item) in items.enumerated() {
                walk(item, path: path, index: index + 1, arrayIndex: i, list: &list, arr: &arr)
            }
            return
        }

        walk(value, path: path, index: index + 1, arrayIndex: arrayIndex, list: &list, arr: &arr)
    }

    private static func scalarString(_ node: JSONValue) -> String? {
        switch node {
        case .string(let s): return s
        case .bool(let b): return Trim.toString(b)
        case .int(let i): return Trim.toString(Int(i))
        case .double(let d): return Trim.toString(d)
        case .null, .array, .object: return nil
        }
    }
}

/// Typed JSON tree, decoded from `JSONEncoder` output. Preserves
/// Bool/Int/Double discrimination that `JSONSerialization`'s `NSNumber`
/// loses, and preserves `null` as a distinct case from missing keys.
enum JSONValue: Decodable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        // Bool must be probed before number — JSONDecoder succeeds on Bool
        // only for true/false, and on number for integers/floats; Bool
        // values would otherwise decode as Int (NSNumber bridging).
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
            return
        }
        // Int before Double so integral JSON numbers stay integral. Double
        // would succeed for "1" but lose the integer-ness.
        if let i = try? c.decode(Int64.self) {
            self = .int(i)
            return
        }
        if let d = try? c.decode(Double.self) {
            self = .double(d)
            return
        }
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        if let arr = try? c.decode([JSONValue].self) {
            self = .array(arr)
            return
        }
        if let obj = try? c.decode([String: JSONValue].self) {
            self = .object(obj)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "unrecognized JSON value shape"
        )
    }
}
