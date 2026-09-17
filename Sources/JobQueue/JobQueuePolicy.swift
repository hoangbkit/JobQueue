public struct JobQueuePolicy: Equatable, Sendable {
    public let maxConcurrentExecutions: Int

    public init(maxConcurrentExecutions: Int) {
        precondition(
            (1...100).contains(maxConcurrentExecutions),
            "maxConcurrentExecutions must be in 1...100."
        )
        self.maxConcurrentExecutions = maxConcurrentExecutions
    }
}
