import Foundation

public struct FileTreeRow: Equatable {
    public let path: String
    /// Text shown for the row: the file name, or a folder chain such as "Sources/Core"
    /// when a folder only holds one sub-folder (tree mode); the full path in flat mode.
    public let name: String
    public let depth: Int
    public let fileIndex: Int?
    public var isDirectory: Bool { fileIndex == nil }
    public static func make(_ files: [ChangedFile], tree: Bool, collapsed: Set<String> = []) -> [FileTreeRow] {
        guard tree else { return files.indices.map { FileTreeRow(path: files[$0].path, name: files[$0].path, depth: 0, fileIndex: $0) } }
        var children: [String: Set<String>] = [:], leaves: [String: Int] = [:]
        for (index, file) in files.enumerated() {
            let components = file.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            var parent = ""
            for component in components {
                let path = parent.isEmpty ? component : parent + "/" + component
                children[parent, default: []].insert(path); parent = path
            }
            leaves[file.path] = index
        }
        var result: [FileTreeRow] = []
        func visit(_ parent: String, depth: Int) {
            let paths = (children[parent] ?? []).sorted { a, b in
                let ad = leaves[a] == nil, bd = leaves[b] == nil
                return ad != bd ? ad : a.localizedStandardCompare(b) == .orderedAscending
            }
            for start in paths {
                var path = start
                // Fold a chain of folders that each hold a single sub-folder into one row.
                while leaves[path] == nil, let only = children[path], only.count == 1, let next = only.first, leaves[next] == nil { path = next }
                let name = parent.isEmpty ? path : String(path.dropFirst(parent.count + 1))
                result.append(FileTreeRow(path: path, name: name, depth: depth, fileIndex: leaves[path]))
                if leaves[path] == nil && !collapsed.contains(path) { visit(path, depth: depth+1) }
            }
        }
        visit("", depth: 0); return result
    }
}
