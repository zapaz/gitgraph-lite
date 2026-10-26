import Foundation

public struct Commit: Equatable {
    public let id: String
    public let parents: [String]
    public let author: String
    public let date: Date
    public let decorations: String
    public let subject: String
    public init(id: String, parents: [String], author: String = "", date: Date = Date(), decorations: String = "", subject: String = "") {
        self.id = id; self.parents = parents; self.author = author
        self.date = date; self.decorations = decorations; self.subject = subject
    }
}

public struct ChangedFile: Equatable {
    public let status: String
    public let path: String
}

public struct Repository {
    public let path: String
    public let branch: String
    public let branches: [String]
    public let commits: [Commit]
    public let signature: String
    public let references: [GitReference]
    public let pendingOperation: String?
    public let worktrees: [GitWorktree]
    public var worktreeSignature: String { Git.worktreeSummary(worktrees) }
}

public struct GitError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public enum Git {
    // Files avoid pipe-buffer deadlocks when either output stream is large.
    public static func run(_ args: [String], at path: String) throws -> Data {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("GitGraphLite-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let out = temp.appendingPathComponent("stdout"), err = temp.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: out), stderr = try FileHandle(forWritingTo: err)
        defer { try? stdout.close(); try? stderr.close() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["--no-optional-locks", "-C", path] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"; env["GIT_PAGER"] = "cat"
        env["GIT_EDITOR"] = "/usr/bin/true"; env["GIT_SEQUENCE_EDITOR"] = "/usr/bin/true"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = stdout; p.standardError = stderr
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let detail = (try? String(contentsOf: err, encoding: .utf8)) ?? "Git command failed."
            throw GitError(message: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Data(contentsOf: out)
    }

    public static func string(_ args: [String], at path: String) throws -> String {
        String(decoding: try run(args, at: path), as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    public static func parseLog(_ data: Data) -> [Commit] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var commits: [Commit] = []
        var i = 0
        while i + 5 < fields.count {
            let f = fields[i..<(i+6)].map { String(decoding: $0, as: UTF8.self) }
            if !f[0].isEmpty {
                commits.append(Commit(id: f[0], parents: f[1].split(separator: " ").map(String.init), author: f[2], date: Date(timeIntervalSince1970: Double(f[3]) ?? 0), decorations: f[4], subject: f[5]))
            }
            i += 6
        }
        return commits
    }

    public static func signature(at path: String) throws -> String {
        let refs = try string(["for-each-ref", "--format=%(refname) %(objectname)"], at: path)
        let head = (try? string(["rev-parse", "--verify", "HEAD"], at: path)) ?? "unborn"
        let branch = (try? string(["symbolic-ref", "--quiet", "--short", "HEAD"], at: path)) ?? "detached"
        return refs + "\n" + head + "\n" + branch + "\n" + (try pendingOperation(at: path) ?? "")
    }

    public static func load(at input: String, branch filter: String?, limit: Int) throws -> Repository {
        let path = try string(["rev-parse", "--show-toplevel"], at: input)
        let branch = (try? string(["symbolic-ref", "--quiet", "--short", "HEAD"], at: path)) ?? "Detached HEAD"
        let branches = try string(["for-each-ref", "--format=%(refname)", "refs/heads", "refs/remotes"], at: path).split(separator: "\n").map(String.init)
        let hasHead = (try? string(["rev-parse", "--verify", "HEAD"], at: path)) != nil
        let trees = try worktrees(at: path)
        var args = ["log", "--date-order", "-z", "--format=%H%x00%P%x00%an%x00%ct%x00%D%x00%s", "--max-count=\(limit)"]
        if let filter, branches.contains(filter) { args += [filter] } else {
            args += ["--all"]; if hasHead { args += ["HEAD"] }
            args += trees.map(\.head).filter { !$0.isEmpty && $0.contains(where: { $0 != "0" }) }
        }
        args += ["--"]
        let commits = hasHead || !branches.isEmpty ? try parseLog(run(args, at: path)) : []
        return Repository(path: path, branch: branch, branches: branches, commits: commits, signature: try signature(at: path), references: try references(at: path), pendingOperation: try pendingOperation(at: path), worktrees: trees)
    }

    public static func message(at path: String, commit: String) throws -> String {
        try string(["show", "-s", "--format=%B", commit, "--"], at: path)
    }

    public static func parseFiles(_ data: Data) -> [ChangedFile] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false)
        var files: [ChangedFile] = []; var i = 0
        while i + 1 < fields.count {
            let status = String(decoding: fields[i], as: UTF8.self).trimmingCharacters(in: .newlines)
            let path = String(decoding: fields[i+1], as: UTF8.self)
            if !status.isEmpty && !path.isEmpty { files.append(ChangedFile(status: status, path: path)) }
            i += 2
        }
        return files
    }

    public static func files(at path: String, target: String, base: String?) throws -> [ChangedFile] {
        let args: [String]
        if let base { args = ["diff", "--name-status", "--no-renames", "-z", base, target, "--"] }
        else { args = ["show", "--format=", "--first-parent", "--name-status", "--no-renames", "-z", target, "--"] }
        return parseFiles(try run(args, at: path))
    }

    public static func patch(at path: String, target: String, base: String?, file: String) throws -> String {
        let flags = ["--no-ext-diff", "--no-textconv", "--no-renames", "--color=never"]
        let args: [String]
        if let base { args = ["diff"] + flags + [base, target, "--", ":(literal)" + file] }
        else { args = ["show", "--format=", "--first-parent"] + flags + [target, "--", ":(literal)" + file] }
        let data = try run(args, at: path)
        let cap = 2_000_000
        let text = String(decoding: data.prefix(cap), as: UTF8.self)
        return text + (data.count > cap ? "\n\n[Preview truncated at 2 MB]" : "")
    }
}
