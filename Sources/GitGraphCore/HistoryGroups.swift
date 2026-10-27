import Foundation

public struct HistoryGroup: Equatable {
    // A branch's commits may be interleaved with other branches in date order.
    public let indices: [Int]
    public let id: String
    public var nodeID: String { "gitgraph-group:" + id }
    public static func make(_ commits: [Commit], graph: [GraphRow], protected: Set<String>, chunkSize: Int = 20) -> [HistoryGroup] {
        guard commits.count == graph.count else { return [] }
        let positions = Dictionary(uniqueKeysWithValues: commits.enumerated().map { ($0.element.id, $0.offset) })
        var children: [String: Int] = [:]
        for commit in commits { for parent in commit.parents { children[parent, default: 0] += 1 } }
        func eligible(_ i: Int) -> Bool {
            let c = commits[i]
            return !protected.contains(c.id) && c.parents.count == 1 && children[c.id] == 1
        }
        var groups: [HistoryGroup] = [], visited = Set<Int>()
        for start in commits.indices where !visited.contains(start) && eligible(start) {
            var chain: [Int] = [], current = start
            while eligible(current) && !visited.contains(current) && chain.count < max(3, chunkSize) {
                chain.append(current); visited.insert(current)
                guard let parent = positions[commits[current].parents[0]], parent > current else { break }
                current = parent
            }
            if chain.count >= 3 { groups.append(HistoryGroup(indices: chain, id: commits[start].id)) }
        }
        return groups
    }
}

public struct HistoryProjection {
    public let indices: [Int]
    public let headers: [Int: HistoryGroup]
    public let commits: [Commit]
    public let graph: [GraphRow]

    public static func make(_ commits: [Commit], groups: [HistoryGroup]) -> HistoryProjection {
        let starts = Dictionary(uniqueKeysWithValues: groups.map { ($0.indices[0], $0) })
        var replacements: [String: String] = [:], hidden = Set<Int>()
        for group in groups {
            for i in group.indices { replacements[commits[i].id] = group.nodeID; hidden.insert(i) }
        }
        func resolve(_ id: String) -> String { replacements[id] ?? id }
        var indices: [Int] = [], headers: [Int: HistoryGroup] = [:], displayed: [Commit] = []
        for i in commits.indices {
            if let group = starts[i] {
                headers[indices.count] = group; indices.append(i)
                let parents = commits[group.indices.last!].parents.map(resolve)
                displayed.append(Commit(id: group.nodeID, parents: parents, date: commits[i].date, subject: "\(group.indices.count) commits"))
            }
            guard !hidden.contains(i) else { continue }
            let c = commits[i]
            indices.append(i)
            displayed.append(Commit(id: c.id, parents: c.parents.map(resolve), author: c.author, date: c.date, decorations: c.decorations, subject: c.subject))
        }
        return HistoryProjection(indices: indices, headers: headers, commits: displayed, graph: GraphLayout.make(displayed))
    }
}
