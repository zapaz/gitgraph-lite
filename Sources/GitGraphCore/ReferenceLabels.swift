import Foundation

public struct ReferenceLabel: Equatable {
    public enum Kind: Equatable { case branch, remote, tag }
    public let kind: Kind
    public let name: String
    public let remotes: [String]
    public let fullNames: [String]
    public let isCurrent: Bool

    public static func make(_ references: [GitReference], currentBranch: String) -> [ReferenceLabel] {
        let refs = references.filter { !$0.symbolic }
        let locals = refs.filter(\.isBranch).sorted { a, b in
            if (a.shortName == currentBranch) != (b.shortName == currentBranch) { return a.shortName == currentBranch }
            return a.shortName < b.shortName
        }
        var used = Set<String>(), labels: [ReferenceLabel] = []
        for local in locals {
            let matching = refs.filter { ref in
                guard ref.name.hasPrefix("refs/remotes/"), ref.target == local.target else { return false }
                let short = ref.shortName
                guard let slash = short.firstIndex(of: "/") else { return false }
                return String(short[short.index(after: slash)...]) == local.shortName
            }.sorted { $0.name < $1.name }
            matching.forEach { used.insert($0.name) }
            labels.append(ReferenceLabel(kind: .branch, name: local.shortName, remotes: matching.compactMap { $0.shortName.split(separator: "/").first.map(String.init) }, fullNames: [local.name] + matching.map(\.name), isCurrent: local.shortName == currentBranch))
        }
        for remote in refs.filter({ $0.name.hasPrefix("refs/remotes/") && !used.contains($0.name) }).sorted(by: { $0.name < $1.name }) {
            labels.append(ReferenceLabel(kind: .remote, name: remote.shortName, remotes: [], fullNames: [remote.name], isCurrent: false))
        }
        for tag in refs.filter(\.isTag).sorted(by: { $0.name < $1.name }) {
            labels.append(ReferenceLabel(kind: .tag, name: tag.shortName, remotes: [], fullNames: [tag.name], isCurrent: false))
        }
        return labels
    }
}
