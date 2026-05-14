/// Max-heap by score: keeps the worst (highest) score at the top so it can be
/// evicted when a better result arrives. Mirrors `../fuse-js/src/tools/MaxHeap.ts`.
struct MaxHeap<Element> {
    let limit: Int
    private(set) var heap: [Element] = []
    private let scoreOf: (Element) -> Double

    init(limit: Int, score: @escaping (Element) -> Double) {
        self.limit = limit
        self.scoreOf = score
    }

    var size: Int { heap.count }

    func shouldInsert(score: Double) -> Bool {
        size < limit || score < scoreOf(heap[0])
    }

    mutating func insert(_ item: Element) {
        if size < limit {
            heap.append(item)
            bubbleUp(size - 1)
        } else if scoreOf(item) < scoreOf(heap[0]) {
            heap[0] = item
            sinkDown(0)
        }
    }

    func extractSorted(by sortFn: (Element, Element) -> Bool) -> [Element] {
        heap.sorted(by: sortFn)
    }

    private mutating func bubbleUp(_ start: Int) {
        var i = start
        while i > 0 {
            let parent = (i - 1) >> 1
            if scoreOf(heap[i]) <= scoreOf(heap[parent]) { break }
            heap.swapAt(i, parent)
            i = parent
        }
    }

    private mutating func sinkDown(_ start: Int) {
        let len = heap.count
        var largest = start
        var i = start
        repeat {
            i = largest
            let left = 2 * i + 1
            let right = 2 * i + 2
            if left < len && scoreOf(heap[left]) > scoreOf(heap[largest]) {
                largest = left
            }
            if right < len && scoreOf(heap[right]) > scoreOf(heap[largest]) {
                largest = right
            }
            if largest != i {
                heap.swapAt(i, largest)
            }
        } while largest != i
    }
}
