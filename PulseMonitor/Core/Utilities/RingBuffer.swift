import Foundation

/// Fixed-capacity ring buffer for efficient mini-graph history.
public struct RingBuffer<Element: Sendable>: Sendable {
    private var storage: [Element?]
    private var head: Int = 0
    public private(set) var count: Int = 0
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    public mutating func append(_ element: Element) {
        storage[head] = element
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }

    public var elements: [Element] {
        guard count > 0 else { return [] }
        var result: [Element] = []
        result.reserveCapacity(count)
        let start = count < capacity ? 0 : head
        for i in 0..<count {
            let index = (start + i) % capacity
            if let value = storage[index] {
                result.append(value)
            }
        }
        return result
    }

    public var latest: Element? {
        guard count > 0 else { return nil }
        let index = (head - 1 + capacity) % capacity
        return storage[index]
    }
}
