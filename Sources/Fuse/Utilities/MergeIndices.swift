/// Merges overlapping or adjacent index ranges into a minimal set. Mirrors
/// `../fuse-js/src/helpers/mergeIndices.ts`.
///
/// Adjacent ranges (`curr.start == last.end + 1`) merge — matching upstream's
/// `curr[0] <= last[1] + 1` predicate.
enum MergeIndices {
    static func merge(_ indices: [FuseRange]) -> [FuseRange] {
        if indices.count <= 1 { return indices }
        let sorted = indices.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            return a.end < b.end
        }
        var merged: [FuseRange] = [sorted[0]]
        for i in 1..<sorted.count {
            let last = merged[merged.count - 1]
            let curr = sorted[i]
            if curr.start <= last.end + 1 {
                merged[merged.count - 1] = FuseRange(
                    start: last.start,
                    end: max(last.end, curr.end)
                )
            } else {
                merged.append(curr)
            }
        }
        return merged
    }
}
