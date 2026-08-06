struct BoundedRingBuffer<Element> {
    let capacity: Int

    private var storage: [Element?]
    private(set) var count = 0
    private var head = 0

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage = Array(repeating: nil, count: capacity)
    }

    var first: Element? {
        guard count > 0 else { return nil }
        return storage[head]
    }

    @discardableResult
    mutating func appendDroppingOldest(_ element: Element) -> Element? {
        if count < capacity {
            let insertionIndex = (head + count) % capacity
            storage[insertionIndex] = element
            count += 1
            return nil
        }

        let dropped = storage[head]
        storage[head] = element
        head = (head + 1) % capacity
        return dropped
    }

    mutating func popFirst() -> Element? {
        guard count > 0 else { return nil }
        let element = storage[head]
        storage[head] = nil
        head = (head + 1) % capacity
        count -= 1
        return element
    }

    @discardableResult
    mutating func removeAll() -> Int {
        let removedCount = count
        storage = Array(repeating: nil, count: capacity)
        count = 0
        head = 0
        return removedCount
    }
}
