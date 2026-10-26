import Foundation

public struct GraphEdge {
    public let from: Int
    public let to: Int
    public let color: Int
    // 0: full row, 1: incoming half, 2: outgoing half
    public let segment: Int
}

public struct GraphRow {
    public let lane: Int
    public let color: Int
    public let edges: [GraphEdge]
    public let width: Int
}

public enum GraphLayout {
    private struct Lane { let id: String; let color: Int }
    public static func make(_ commits: [Commit]) -> [GraphRow] {
        var lanes: [Lane] = []; var nextColor = 0; var result: [GraphRow] = []
        for commit in commits {
            var incoming = true
            let index: Int
            if let found = lanes.firstIndex(where: { $0.id == commit.id }) { index = found }
            else { index = lanes.count; lanes.append(Lane(id: commit.id, color: nextColor)); nextColor += 1; incoming = false }
            let before = lanes
            let color = lanes[index].color
            lanes.remove(at: index)
            for (n, parent) in commit.parents.enumerated() where !lanes.contains(where: { $0.id == parent }) {
                if n == 0 { lanes.insert(Lane(id: parent, color: color), at: min(index, lanes.count)) }
                else { lanes.append(Lane(id: parent, color: nextColor)); nextColor += 1 }
            }
            var edges: [GraphEdge] = []
            for (i, lane) in before.enumerated() where i != index {
                if let j = lanes.firstIndex(where: { $0.id == lane.id }) {
                    edges.append(GraphEdge(from: i, to: j, color: lane.color, segment: 0))
                }
            }
            if incoming { edges.append(GraphEdge(from: index, to: index, color: color, segment: 1)) }
            for parent in commit.parents {
                if let j = lanes.firstIndex(where: { $0.id == parent }) {
                    edges.append(GraphEdge(from: index, to: j, color: lanes[j].color, segment: 2))
                }
            }
            result.append(GraphRow(lane: index, color: color, edges: edges, width: max(before.count, lanes.count)))
        }
        return result
    }
}
