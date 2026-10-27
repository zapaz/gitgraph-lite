import Foundation

public struct HistoryGroup: Equatable {
    public let indices: Range<Int>
    public let id: String
    // Only fold straight, uninterrupted chains. References, junctions and lane changes remain visible.
    public static func make(_ commits: [Commit], graph: [GraphRow], protected: Set<String>, chunkSize: Int = 20) -> [HistoryGroup] {
        guard commits.count == graph.count else { return [] }
        var children: [String: Int] = [:]
        for commit in commits { for parent in commit.parents { children[parent, default: 0] += 1 } }
        func eligible(_ i: Int) -> Bool {
            let c = commits[i], g = graph[i]
            return !protected.contains(c.id) && c.parents.count == 1 && children[c.id] == 1 && g.edges.allSatisfy { $0.from == $0.to } && g.edges.contains { $0.segment == 1 } && g.edges.contains { $0.segment == 2 }
        }
        var groups: [HistoryGroup] = [], i = 0
        let size = max(5, chunkSize)
        while i < commits.count {
            guard eligible(i) else { i += 1; continue }
            let start = i; i += 1
            while i < commits.count && eligible(i) && commits[i-1].parents == [commits[i].id] && graph[i].lane == graph[start].lane && graph[i].width == graph[start].width && i-start < size { i += 1 }
            if i-start >= 5 { groups.append(HistoryGroup(indices: start..<i, id: commits[start].id)) }
        }
        return groups
    }
}
