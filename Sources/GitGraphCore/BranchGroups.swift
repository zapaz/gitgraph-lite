import Foundation

public struct BranchGroup: Equatable {
    public let name: String
    public let references: [String]
    public var mandatoryPin: Bool { name == "main" || name == "master" }
    public var localReference: String? { references.first { $0.hasPrefix("refs/heads/") } }
    public static func make(_ refs: [GitReference], remotes: [String]) -> [BranchGroup] {
        let prefixes = remotes.sorted { $0.count > $1.count }.map { "refs/remotes/" + $0 + "/" }
        var grouped: [String: [String]] = [:]
        for ref in refs where !ref.symbolic {
            let name: String
            if ref.isBranch { name = ref.shortName }
            else if let prefix = prefixes.first(where: { ref.name.hasPrefix($0) }) { name = String(ref.name.dropFirst(prefix.count)) }
            else { continue }
            grouped[name, default: []].append(ref.name)
        }
        return grouped.keys.sorted().map { BranchGroup(name: $0, references: grouped[$0]!.sorted()) }
    }
    // nil means all branches; an empty selection still includes pinned branches.
    public static func historyReferences(_ groups: [BranchGroup], selection: Set<String>?, pins: Set<String>) -> [String]? {
        guard let selection else { return nil }
        return groups.filter { $0.mandatoryPin || pins.contains($0.name) || selection.contains($0.name) }.flatMap(\.references)
    }
}
