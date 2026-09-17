import Foundation

struct JobScheduler {
    private static let priorityCycle: [JobPriority] =
        Array(repeating: .userInitiated, count: 8) +
        Array(repeating: .default, count: 4) +
        Array(repeating: .utility, count: 2) +
        [.background]

    private var priorityCursor = 0
    private var typeCursors: [JobPriority: Int] = [:]

    mutating func nextJobID(
        records: [UUID: JobRecord],
        immediateJobIDs: [UUID],
        pausedTypeNames: Set<String>,
        runningCountByType: [String: Int],
        concurrencyLimit: (String) -> Int?
    ) -> UUID? {
        if let immediate = immediateJobIDs.first(where: {
            guard let record = records[$0], record.status == .pending else {
                return false
            }
            return isEligible(
                record,
                pausedTypeNames: pausedTypeNames,
                runningCountByType: runningCountByType,
                concurrencyLimit: concurrencyLimit
            )
        }) {
            return immediate
        }

        for offset in 0..<Self.priorityCycle.count {
            let cycleIndex = (priorityCursor + offset) % Self.priorityCycle.count
            let priority = Self.priorityCycle[cycleIndex]
            let candidates = records.values.filter {
                $0.status == .pending &&
                $0.priority == priority &&
                isEligible(
                    $0,
                    pausedTypeNames: pausedTypeNames,
                    runningCountByType: runningCountByType,
                    concurrencyLimit: concurrencyLimit
                )
            }
            guard !candidates.isEmpty else { continue }

            let typeNames = Array(Set(candidates.map(\.typeName))).sorted()
            let typeCursor = typeCursors[priority, default: 0] % typeNames.count
            let typeName = typeNames[typeCursor]
            typeCursors[priority] = (typeCursor + 1) % typeNames.count
            priorityCursor = (cycleIndex + 1) % Self.priorityCycle.count

            return candidates
                .filter { $0.typeName == typeName }
                .min(by: Self.isEarlier)?
                .id
        }

        return nil
    }

    private func isEligible(
        _ record: JobRecord,
        pausedTypeNames: Set<String>,
        runningCountByType: [String: Int],
        concurrencyLimit: (String) -> Int?
    ) -> Bool {
        guard !pausedTypeNames.contains(record.typeName) else { return false }
        guard let limit = concurrencyLimit(record.typeName) else { return false }
        return runningCountByType[record.typeName, default: 0] < limit
    }

    private static func isEarlier(_ lhs: JobRecord, _ rhs: JobRecord) -> Bool {
        if lhs.enqueueSequence != rhs.enqueueSequence {
            return lhs.enqueueSequence < rhs.enqueueSequence
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
