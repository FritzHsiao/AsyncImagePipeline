import Foundation

/// Coalesces concurrent work for the same key onto a single underlying `Task`, with per-caller
/// cancellation that is **reference-counted**: cancelling one caller only cancels the shared work
/// when it was the *last* interested caller. Siblings awaiting the same key are never starved.
///
/// Isolated as an `actor`, so the in-flight registry needs no locks.
actor DeduplicatingTaskPool {
    /// One shared unit of work plus the set of callers currently interested in its result.
    private final class Job {
        let task: Task<ImageContainer, Error>
        /// One token per live caller; the job is torn down when this empties.
        var subscribers: Set<UUID> = []
        init(task: Task<ImageContainer, Error>) { self.task = task }
    }

    private var jobs: [String: Job] = [:]

    /// Returns the shared result for `key`, starting `operation` only if no job is in flight.
    ///
    /// - The `operation` runs at most once per in-flight key (deduplication).
    /// - If the calling task is cancelled, this caller stops waiting and throws `CancellationError`;
    ///   the shared `operation` is cancelled only once every caller has withdrawn.
    func perform(
        key: String,
        priority: TaskPriority,
        operation: @escaping @Sendable () async throws -> ImageContainer
    ) async throws -> ImageContainer {
        let token = UUID()
        let task = register(key: key, token: token, priority: priority, operation: operation)

        return try await withTaskCancellationHandler {
            do {
                let value = try await task.value
                withdraw(key: key, token: token, cancelIfLast: false)
                // If *this* caller was cancelled while siblings kept the job alive, honor it now.
                try Task.checkCancellation()
                return value
            } catch {
                withdraw(key: key, token: token, cancelIfLast: false)
                throw error
            }
        } onCancel: {
            Task { await self.withdraw(key: key, token: token, cancelIfLast: true) }
        }
    }

    /// The number of jobs currently in flight — exposed for tests.
    var inFlightCount: Int { jobs.count }

    // MARK: Registry

    private func register(
        key: String,
        token: UUID,
        priority: TaskPriority,
        operation: @escaping @Sendable () async throws -> ImageContainer
    ) -> Task<ImageContainer, Error> {
        if let existing = jobs[key] {
            existing.subscribers.insert(token)
            return existing.task
        }
        let task = Task<ImageContainer, Error>(priority: priority) {
            try await operation()
        }
        let job = Job(task: task)
        job.subscribers.insert(token)
        jobs[key] = job
        return task
    }

    /// Removes a caller's interest. Idempotent per token, so the completion path and the
    /// cancellation path can both call it without double-counting.
    private func withdraw(key: String, token: UUID, cancelIfLast: Bool) {
        guard let job = jobs[key], job.subscribers.contains(token) else { return }
        job.subscribers.remove(token)

        if job.subscribers.isEmpty {
            if cancelIfLast {
                job.task.cancel()
            }
            // Drop the entry so the next request re-checks the caches and (if needed) starts fresh.
            jobs[key] = nil
        }
    }
}
